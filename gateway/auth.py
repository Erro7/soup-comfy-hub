import hmac

from fastapi import Header, HTTPException, status

from .config import get_settings


async def require_api_key(authorization: str | None = Header(default=None)) -> None:
    expected = get_settings().api_key
    if expected == "change-me":
        raise HTTPException(status_code=503, detail="API_KEY is not configured")
    prefix = "Bearer "
    if not authorization or not authorization.startswith(prefix):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Bearer token")
    if not hmac.compare_digest(authorization[len(prefix):], expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")
