import asyncio
from pathlib import Path

import httpx


class ComfyClient:
    def __init__(self, base_url: str, timeout: int):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    async def health(self) -> dict:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{self.base_url}/system_stats")
            response.raise_for_status()
            return response.json()

    async def free(self) -> None:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(f"{self.base_url}/free", json={"unload_models": True, "free_memory": True})
            response.raise_for_status()

    async def upload(self, path: Path) -> str:
        async with httpx.AsyncClient(timeout=120) as client, path.open("rb") as handle:
            response = await client.post(f"{self.base_url}/upload/image", files={"image": (path.name, handle, "application/octet-stream")}, data={"overwrite": "true"})
            response.raise_for_status()
            data = response.json()
            return "/".join(filter(None, (data.get("subfolder"), data["name"])))

    async def submit(self, workflow: dict) -> str:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(f"{self.base_url}/prompt", json={"prompt": workflow})
            response.raise_for_status()
            data = response.json()
            if "prompt_id" not in data:
                raise RuntimeError(f"ComfyUI rejected workflow: {data}")
            return data["prompt_id"]

    async def wait_history(self, prompt_id: str) -> dict:
        deadline = asyncio.get_running_loop().time() + self.timeout
        async with httpx.AsyncClient(timeout=30) as client:
            while asyncio.get_running_loop().time() < deadline:
                response = await client.get(f"{self.base_url}/history/{prompt_id}")
                response.raise_for_status()
                data = response.json()
                if prompt_id in data:
                    record = data[prompt_id]
                    status = record.get("status", {})
                    if status.get("status_str") == "error":
                        raise RuntimeError(f"ComfyUI execution failed: {status}")
                    return record
                await asyncio.sleep(2)
        raise TimeoutError(f"ComfyUI prompt timed out: {prompt_id}")

    async def view(self, item: dict) -> bytes:
        params = {key: item[key] for key in ("filename", "subfolder", "type") if key in item}
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.get(f"{self.base_url}/view", params=params)
            response.raise_for_status()
            return response.content
