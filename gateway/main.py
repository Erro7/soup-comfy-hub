import asyncio
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import FileResponse

from .auth import require_api_key
from .comfy_client import ComfyClient
from .comfy_router import ImageRouter
from .config import get_settings
from .schemas import ImageEditRequest, PortraitVideoRequest, SoupTrainRequest, VideoGenerationRequest
from .soup_runner import SoupRunner
from .task_store import TaskStore
from .video_router import VideoRouter
from .vram_manager import VRAMManager

settings = get_settings()
comfy = ComfyClient(settings.comfy_url, settings.comfy_timeout_seconds)
tasks = TaskStore(settings.task_db_path)
vram = VRAMManager(comfy)
images = ImageRouter(settings, comfy, vram)
videos = VideoRouter(settings, comfy, vram, tasks)
soup = SoupRunner(settings, vram, tasks) if settings.enable_soup else None


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings.task_output_dir.mkdir(parents=True, exist_ok=True)
    yield


app = FastAPI(title="Soup-Comfy-Hub", version="2.1.0", lifespan=lifespan)


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "service": "gateway"}


@app.get("/readyz")
async def readyz():
    try:
        await comfy.health()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="ComfyUI is unavailable") from exc
    return {"status": "ready", "comfyui": "ok", "soup_enabled": settings.enable_soup}


@app.post("/v1/images/edits", dependencies=[Depends(require_api_key)])
async def image_edits(request: ImageEditRequest):
    return await images.generate(request)


@app.post("/v1/videos/generations", dependencies=[Depends(require_api_key)])
async def video_generations(request: VideoGenerationRequest):
    if request.async_mode:
        task = videos.enqueue(request)
        return {"task_id": task["id"], "status": task["status"]}
    return await videos.generate(request)


@app.post("/v1/pipelines/portrait-to-video", dependencies=[Depends(require_api_key)])
async def portrait_to_video(request: PortraitVideoRequest):
    task = tasks.create("portrait_to_video")

    async def run():
        tasks.update(task["id"], status="running", progress=0.05)
        try:
            image = await images.generate(ImageEditRequest(
                face_image_b64=request.face_image_b64,
                outfit_image_b64=request.outfit_image_b64,
                pose_image_b64=request.pose_image_b64,
                prompt=request.portrait_prompt,
            ))
            tasks.update(task["id"], progress=0.4)
            payload = request.model_copy(update={"first_frame_b64": image["image_base64"], "async_mode": False})
            fields = set(VideoGenerationRequest.model_fields)
            result = await videos.generate(VideoGenerationRequest(**payload.model_dump(include=fields)))
            tasks.update(task["id"], status="succeeded", progress=1, result=result)
        except Exception as exc:
            tasks.update(task["id"], status="failed", error=str(exc))

    asyncio.create_task(run())
    return {"task_id": task["id"], "status": task["status"]}


@app.get("/v1/tasks/{task_id}", dependencies=[Depends(require_api_key)])
async def get_task(task_id: str):
    task = tasks.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@app.get("/v1/files/{filename}", dependencies=[Depends(require_api_key)])
async def get_file(filename: str):
    path = (settings.task_output_dir / filename).resolve()
    if path.parent != settings.task_output_dir.resolve() or not path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(path)


if settings.enable_soup:
    @app.post("/v1/soup/train", dependencies=[Depends(require_api_key)])
    async def soup_train(request: SoupTrainRequest):
        assert soup is not None
        task = soup.enqueue(request)
        return {"task_id": task["id"], "status": task["status"]}


if settings.enable_gradio_ui:
    import gradio as gr

    with gr.Blocks(title="Soup-Comfy-Hub") as demo:
        gr.Markdown("# Soup-Comfy-Hub\nAPI-first ComfyUI image and video orchestration console.")
        gr.Markdown("Production clients should use the authenticated REST API under `/v1`.")
        with gr.Tab("Image workflow"):
            gr.Markdown("Use `POST /v1/images/edits`.")
        with gr.Tab("Video workflow"):
            gr.Markdown("Use `POST /v1/videos/generations` and poll `/v1/tasks/{task_id}`.")
        if settings.enable_soup:
            with gr.Tab("Soup"):
                gr.Markdown("Optional training is available through `POST /v1/soup/train`.")

    app = gr.mount_gradio_app(app, demo, path="/ui")
