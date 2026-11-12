from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    api_key: str = "change-me"
    cluster_key: str = "change-cluster-key"
    require_cluster_key: bool = False
    enable_soup: bool = False
    enable_gradio_ui: bool = False
    comfy_url: str = "http://127.0.0.1:8188"
    comfy_output_dir: Path = Path("/mnt/workspace/ComfyUI/output")
    comfy_input_dir: Path = Path("/mnt/workspace/ComfyUI/input")
    workflow_dir: Path = Path("workflows")
    soup_workspace: Path = Path("soup_workspace")
    task_output_dir: Path = Path("outputs")
    task_db_path: Path = Path("outputs/tasks.sqlite3")
    comfy_timeout_seconds: int = 3600
    max_upload_mb: int = 40
    default_video_width: int = 720
    default_video_height: int = 1280
    default_video_frames: int = 81
    default_video_fps: int = 16


@lru_cache
def get_settings() -> Settings:
    return Settings()
