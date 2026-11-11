import asyncio
import os
from pathlib import Path

from .config import Settings
from .schemas import SoupTrainRequest
from .task_store import TaskStore
from .vram_manager import VRAMManager, Workload


class SoupRunner:
    def __init__(self, settings: Settings, vram: VRAMManager, tasks: TaskStore):
        self.settings, self.vram, self.tasks = settings, vram, tasks

    def enqueue(self, request: SoupTrainRequest) -> dict:
        task = self.tasks.create("soup_train")
        asyncio.create_task(self._run(task["id"], request))
        return task

    async def _run(self, task_id: str, request: SoupTrainRequest):
        self.tasks.update(task_id, status="running", progress=0.05)
        try:
            root = self.settings.soup_workspace.resolve()
            config = (root / request.config_path).resolve()
            if root not in config.parents or not config.is_file():
                raise ValueError("config_path must be an existing file inside SOUP_WORKSPACE")
            log_dir = self.settings.task_output_dir / "logs"
            log_dir.mkdir(parents=True, exist_ok=True)
            log_path = log_dir / f"{task_id}.log"
            env = os.environ.copy()
            async with self.vram.acquire(Workload.TRAIN):
                with log_path.open("wb") as log:
                    process = await asyncio.create_subprocess_exec(
                        "soup", "train", "--config", str(config), *request.extra_args,
                        cwd=root, stdout=log, stderr=asyncio.subprocess.STDOUT, env=env,
                    )
                    code = await process.wait()
            if code:
                raise RuntimeError(f"soup train exited with code {code}; see {log_path}")
            self.tasks.update(task_id, status="succeeded", progress=1, result={"log": str(log_path)})
        except Exception as exc:
            self.tasks.update(task_id, status="failed", error=str(exc))
