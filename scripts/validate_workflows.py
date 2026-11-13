#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED = {
    "multi_ref_portrait.json": {
        "LOAD_FACE", "LOAD_OUTFIT", "LOAD_POSE", "PROMPT_POSITIVE", "IMAGE_OUTPUT"
    },
    "wan21_i2v_vertical.json": {
        "LOAD_FIRST_FRAME", "PROMPT_POSITIVE", "PROMPT_NEGATIVE",
        "VIDEO_LATENT_CONFIG", "VIDEO_OUTPUT",
    },
}

failed = False
workflows: dict[str, dict] = {}
for filename, anchors in REQUIRED.items():
    path = Path("workflows") / filename
    payload = json.loads(path.read_text())
    workflow = payload.get("prompt", payload)
    workflows[filename] = workflow
    titles = {node.get("_meta", {}).get("title") for node in workflow.values()}
    missing = anchors - titles
    if missing:
        failed = True
        print(f"{filename}: missing anchors {sorted(missing)}", file=sys.stderr)

manifest_path = Path("config/model-profiles/image.tsv")
targets: set[str] = set()
for line_number, raw in enumerate(manifest_path.read_text().splitlines(), 1):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split("|")
    if len(parts) != 4:
        failed = True
        print(f"{manifest_path}:{line_number}: expected four fields", file=sys.stderr)
        continue
    kind, repository, source, target = parts
    if kind not in {"file", "tree", "archive"} or not repository or not source or not target:
        failed = True
        print(f"{manifest_path}:{line_number}: invalid model entry", file=sys.stderr)
    target_path = Path(target)
    if target_path.is_absolute() or ".." in target_path.parts:
        failed = True
        print(f"{manifest_path}:{line_number}: unsafe target {target}", file=sys.stderr)
    if target in targets:
        failed = True
        print(f"{manifest_path}:{line_number}: duplicate target {target}", file=sys.stderr)
    targets.add(target)

portrait = workflows["multi_ref_portrait.json"]
model_inputs: set[str] = set()
for node in portrait.values():
    for value in node.get("inputs", {}).values():
        if isinstance(value, str) and value.lower().endswith((".safetensors", ".bin")):
            model_inputs.add(value)

for model_input in sorted(model_inputs):
    if not any(target == model_input or target.endswith(f"/{model_input}") for target in targets):
        failed = True
        print(
            f"multi_ref_portrait.json: model {model_input!r} is not provided by image.tsv",
            file=sys.stderr,
        )

if failed:
    raise SystemExit(1)
print("Workflow anchors and model manifests are valid")
