import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path


class TaskStore:
    def __init__(self, db_path: Path):
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = db_path
        self._lock = threading.Lock()
        self._init()

    def _connect(self):
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init(self):
        with self._connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY, kind TEXT NOT NULL, status TEXT NOT NULL,
                progress REAL NOT NULL DEFAULT 0, result TEXT, error TEXT,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            )""")

    def create(self, kind: str) -> dict:
        task_id, now = str(uuid.uuid4()), datetime.now(timezone.utc).isoformat()
        with self._lock, self._connect() as db:
            db.execute("INSERT INTO tasks(id,kind,status,created_at,updated_at) VALUES(?,?,?,?,?)", (task_id, kind, "pending", now, now))
        return self.get(task_id)

    def update(self, task_id: str, **values) -> dict:
        allowed = {"status", "progress", "result", "error"}
        values = {k: v for k, v in values.items() if k in allowed}
        if "result" in values and values["result"] is not None:
            values["result"] = json.dumps(values["result"])
        values["updated_at"] = datetime.now(timezone.utc).isoformat()
        assignments = ",".join(f"{key}=?" for key in values)
        with self._lock, self._connect() as db:
            db.execute(f"UPDATE tasks SET {assignments} WHERE id=?", (*values.values(), task_id))
        return self.get(task_id)

    def get(self, task_id: str) -> dict | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()
        if not row:
            return None
        data = dict(row)
        data["result"] = json.loads(data["result"]) if data["result"] else None
        return data
