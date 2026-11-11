import asyncio
from pathlib import Path

from .comfy_client import ComfyClient
from .config import Settings
from .media import save_input
from .schemas import VideoGenerationRequest
from .task_store import TaskStore
from .vram_manager import VRAMManager, Workload
from .workflow import find_by_title, load_workflow, set_first


class VideoRouter:
    def __init__(self, settings: Settings, comfy: ComfyClient, vram: VRAMManager, tasks: TaskStore):
        self.settings, self.comfy, self.vram, self.tasks = settings, comfy, vram, tasks

    def enqueue(self, request: VideoGenerationRequest) -> dict:
        task = self.tasks.create("video")
        asyncio.create_task(self._run(task["id"], request))
        return task

    async def generate(self, request: VideoGenerationRequest) -> dict:
        return await self._generate(request)

    async def _run(self, task_id: str, request: VideoGenerationRequest):
        self.tasks.update(task_id, status="running", progress=0.05)
        try:
            result = await self._generate(request)
            self.tasks.update(task_id, status="succeeded", progress=1, result=result)
        except Exception as exc:
            self.tasks.update(task_id, status="failed", error=str(exc))

    async def _generate(self, request: VideoGenerationRequest) -> dict:
        paths: list[Path] = []
        try:
            first = save_input(request.first_frame_b64, self.settings.comfy_input_dir, "first", self.settings.max_upload_mb)
            paths.append(first)
            uploaded = {"first": await self.comfy.upload(first)}
            if request.last_frame_b64:
                last = save_input(request.last_frame_b64, self.settings.comfy_input_dir, "last", self.settings.max_upload_mb)
                paths.append(last)
                uploaded["last"] = await self.comfy.upload(last)
            if request.control_video_b64:
                control = save_input(request.control_video_b64, self.settings.comfy_input_dir, "control", self.settings.max_upload_mb, ".mp4")
                paths.append(control)
                uploaded["control"] = await self.comfy.upload(control)
            workflow = load_workflow(self.settings.workflow_dir / "wan21_i2v_vertical.json")
            set_first(find_by_title(workflow, "LOAD_FIRST_FRAME"), ("image",), uploaded["first"])
            optional = (("LOAD_LAST_FRAME", "last", ("image",)), ("LOAD_REF_VIDEO", "control", ("video",)))
            for title, key, fields in optional:
                if key in uploaded:
                    node = find_by_title(workflow, title, required=False)
                    if not node:
                        raise ValueError(f"Request includes {key}, but workflow has no {title} anchor")
                    set_first(node, fields, uploaded[key])
            set_first(find_by_title(workflow, "PROMPT_POSITIVE"), ("text", "positive_prompt"), request.prompt)
            set_first(find_by_title(workflow, "PROMPT_NEGATIVE"), ("text", "negative_prompt"), request.negative_prompt)
            latent = find_by_title(workflow, "VIDEO_LATENT_CONFIG")
            for fields, value in ((('width',), request.width), (('height',), request.height), (('length', 'num_frames'), request.num_frames)):
                set_first(latent, fields, value)
            set_first(find_by_title(workflow, "VIDEO_OUTPUT"), ("frame_rate", "fps"), request.fps)
            async with self.vram.acquire(Workload.VIDEO):
                prompt_id = await self.comfy.submit(workflow)
                history = await self.comfy.wait_history(prompt_id)
            item = extract_video_item(history)
            raw = await self.comfy.view(item)
            extension = Path(item["filename"]).suffix or ".mp4"
            self.settings.task_output_dir.mkdir(parents=True, exist_ok=True)
            output = self.settings.task_output_dir / f"{prompt_id}{extension}"
            output.write_bytes(raw)
            return {"prompt_id": prompt_id, "filename": output.name, "download_url": f"/v1/files/{output.name}"}
        finally:
            for path in paths:
                path.unlink(missing_ok=True)


def extract_video_item(history: dict) -> dict:
    for output in history.get("outputs", {}).values():
        for key in ("gifs", "videos", "images"):
            for item in output.get(key, []):
                if item.get("filename", "").lower().endswith((".mp4", ".webm", ".mov")):
                    return item
    raise RuntimeError("No MP4/WebM/MOV output found in ComfyUI history")
