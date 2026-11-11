import base64
import json
from pathlib import Path

import pytest

from gateway.media import decode_b64
from gateway.task_store import TaskStore
from gateway.video_router import extract_video_item
from gateway.workflow import WorkflowError, find_by_title, load_workflow


def test_decode_data_url():
    raw, mime = decode_b64("data:image/png;base64," + base64.b64encode(b"png").decode(), 1)
    assert raw == b"png"
    assert mime == "image/png"


def test_task_store(tmp_path):
    store = TaskStore(tmp_path / "tasks.db")
    task = store.create("video")
    updated = store.update(task["id"], status="succeeded", result={"filename": "x.mp4"})
    assert updated["result"]["filename"] == "x.mp4"


def test_video_extraction_supports_gifs():
    item = {"filename": "x.mp4", "subfolder": "video", "type": "output"}
    assert extract_video_item({"outputs": {"13": {"gifs": [item]}}}) == item


def test_find_anchor():
    workflow = {"1": {"_meta": {"title": "A"}, "inputs": {}}}
    assert find_by_title(workflow, "A") == workflow["1"]


def test_template_workflow_rejected(tmp_path):
    path = tmp_path / "template.json"
    path.write_text(json.dumps({"template_only": True, "notice": "replace me", "prompt": {}}))
    with pytest.raises(WorkflowError, match="replace me"):
        load_workflow(path)


def test_portrait_workflow_is_runnable_baseline():
    workflow = load_workflow(Path("workflows/multi_ref_portrait.json"))
    titles = {node.get("_meta", {}).get("title") for node in workflow.values()}
    assert {"LOAD_FACE", "LOAD_OUTFIT", "LOAD_POSE", "APPLY_FACE_AND_POSE", "APPLY_OUTFIT", "IMAGE_OUTPUT"} <= titles
