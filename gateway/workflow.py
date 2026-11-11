import copy
import json
from pathlib import Path


class WorkflowError(RuntimeError):
    pass


def load_workflow(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("template_only"):
        raise WorkflowError(data.get("notice", f"Workflow template must be replaced: {path}"))
    workflow = data.get("prompt", data)
    if not isinstance(workflow, dict):
        raise WorkflowError(f"Invalid API workflow: {path}")
    return copy.deepcopy(workflow)


def find_by_title(workflow: dict, title: str, required: bool = True) -> dict | None:
    for node in workflow.values():
        if node.get("_meta", {}).get("title") == title:
            return node
    if required:
        raise WorkflowError(f"Workflow anchor missing: {title}")
    return None


def set_first(node: dict, names: tuple[str, ...], value) -> None:
    inputs = node.setdefault("inputs", {})
    for name in names:
        if name in inputs:
            inputs[name] = value
            return
    inputs[names[0]] = value
