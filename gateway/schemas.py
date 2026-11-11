from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ImageEditRequest(BaseModel):
    face_image_b64: str
    outfit_image_b64: str
    pose_image_b64: str
    prompt: str = "85mm commercial portrait, realistic skin texture, editorial lighting"
    negative_prompt: str = "low quality, distorted face, extra fingers"
    seed: int = -1


class VideoGenerationRequest(BaseModel):
    first_frame_b64: str
    last_frame_b64: str | None = None
    control_video_b64: str | None = None
    prompt: str
    negative_prompt: str = "flicker, distortion, low quality, deformed anatomy"
    width: int = Field(default=720, ge=256, le=1536)
    height: int = Field(default=1280, ge=256, le=1536)
    num_frames: int = Field(default=81, ge=9, le=241)
    fps: int = Field(default=16, ge=1, le=60)
    seed: int = -1
    async_mode: bool = True

    @model_validator(mode="after")
    def validate_pixels(self):
        if self.width % 16 or self.height % 16:
            raise ValueError("width and height must be multiples of 16")
        return self


class PortraitVideoRequest(VideoGenerationRequest):
    first_frame_b64: str = ""
    face_image_b64: str
    outfit_image_b64: str
    pose_image_b64: str
    portrait_prompt: str = "85mm commercial portrait, realistic skin texture, editorial lighting"


class SoupTrainRequest(BaseModel):
    config_path: str = "soup.yaml"
    extra_args: list[str] = Field(default_factory=list)


class TaskResponse(BaseModel):
    task_id: str
    status: Literal["pending", "running", "succeeded", "failed"]
    kind: str
    progress: float = 0
    result_url: str | None = None
    result: dict | None = None
    error: str | None = None
