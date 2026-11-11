import base64
import binascii
import re
import uuid
from pathlib import Path


DATA_URL = re.compile(r"^data:(?P<mime>[-\w.+/]+);base64,(?P<data>.*)$", re.DOTALL)


def decode_b64(value: str, limit_mb: int) -> tuple[bytes, str | None]:
    match = DATA_URL.match(value)
    mime, payload = (match.group("mime"), match.group("data")) if match else (None, value)
    try:
        raw = base64.b64decode(payload, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("Invalid base64 media") from exc
    if len(raw) > limit_mb * 1024 * 1024:
        raise ValueError(f"Media exceeds {limit_mb} MB limit")
    return raw, mime


def save_input(value: str, directory: Path, stem: str, limit_mb: int, default_ext: str = ".png") -> Path:
    raw, mime = decode_b64(value, limit_mb)
    extensions = {"image/jpeg": ".jpg", "image/webp": ".webp", "video/mp4": ".mp4", "video/webm": ".webm"}
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"sch_{stem}_{uuid.uuid4().hex}{extensions.get(mime, default_ext)}"
    path.write_bytes(raw)
    return path
