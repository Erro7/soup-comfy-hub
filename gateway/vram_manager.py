import asyncio
import gc
from contextlib import asynccontextmanager
from enum import StrEnum

from .comfy_client import ComfyClient


class Workload(StrEnum):
    IMAGE = "image"
    VIDEO = "video"
    TRAIN = "train"


class VRAMManager:
    """Serializes all GPU workloads and unloads ComfyUI at mode boundaries."""

    def __init__(self, comfy: ComfyClient):
        self.comfy = comfy
        self.lock = asyncio.Lock()
        self.active: Workload | None = None

    async def release(self):
        try:
            await self.comfy.free()
        finally:
            gc.collect()

    @asynccontextmanager
    async def acquire(self, workload: Workload):
        async with self.lock:
            if self.active != workload:
                await self.release()
            self.active = workload
            try:
                yield
            finally:
                if workload == Workload.TRAIN:
                    self.active = None
