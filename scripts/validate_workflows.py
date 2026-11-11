#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED = {
    "multi_ref_portrait.json": {"LOAD_FACE", "LOAD_OUTFIT", "LOAD_POSE", "PROMPT_POSITIVE"},
    "wan21_i2v_vertical.json": {"LOAD_FIRST_FRAME", "PROMPT_POSITIVE", "PROMPT_NEGATIVE", "VIDEO_LATENT_CONFIG", "VIDEO_OUTPUT"},
}

failed = False
for filename, anchors in REQUIRED.items():
    path = Path("workflows") / filename
    payload = json.loads(path.read_text())
    workflow = payload.get("prompt", payload)
    titles = {node.get("_meta", {}).get("title") for node in workflow.values()}
    missing = anchors - titles
    if missing:
        failed = True
        print(f"{filename}: missing {sorted(missing)}", file=sys.stderr)
if failed:
    raise SystemExit(1)
print("Workflow anchors are valid")
