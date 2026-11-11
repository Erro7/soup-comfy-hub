import base64
from pathlib import Path

from .comfy_client import ComfyClient
from .config import Settings
from .media import save_input
from .schemas import ImageEditRequest
from .vram_manager import VRAMManager, Workload
from .workflow import find_by_title, load_workflow, set_first


class ImageRouter:
    def __init__(self, settings: Settings, comfy: ComfyClient, vram: VRAMManager):
        self.settings, self.comfy, self.vram = settings, comfy, vram

    async def generate(self, request: ImageEditRequest) -> dict:
        paths: list[Path] = []
        try:
            values = {}
            for key, value in (("face", request.face_image_b64), ("outfit", request.outfit_image_b64), ("pose", request.pose_image_b64)):
                path = save_input(value, self.settings.comfy_input_dir, key, self.settings.max_upload_mb)
                paths.append(path)
                values[key] = await self.comfy.upload(path)
            workflow = load_workflow(self.settings.workflow_dir / "multi_ref_portrait.json")
            for title, key in (("LOAD_FACE", "face"), ("LOAD_OUTFIT", "outfit"), ("LOAD_POSE", "pose")):
                set_first(find_by_title(workflow, title), ("image",), values[key])
            set_first(find_by_title(workflow, "PROMPT_POSITIVE"), ("text", "positive_prompt"), request.prompt)
            negative = find_by_title(workflow, "PROMPT_NEGATIVE", required=False)
            if negative:
                set_first(negative, ("text", "negative_prompt"), request.negative_prompt)
            if request.seed >= 0:
                set_first(find_by_title(workflow, "PORTRAIT_SAMPLER"), ("seed", "noise_seed"), request.seed)
            async with self.vram.acquire(Workload.IMAGE):
                prompt_id = await self.comfy.submit(workflow)
                history = await self.comfy.wait_history(prompt_id)
            item = _find_image(history)
            raw = await self.comfy.view(item)
            return {"image_base64": base64.b64encode(raw).decode(), "prompt_id": prompt_id}
        finally:
            for path in paths:
                path.unlink(missing_ok=True)


def _find_image(history: dict) -> dict:
    for output in history.get("outputs", {}).values():
        for item in output.get("images", []):
            if item.get("filename", "").lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
                return item
    raise RuntimeError("No generated image found in ComfyUI history")
