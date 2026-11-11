import hmac

from fastapi import Header, HTTPException, status

from .config import get_settings


async def require_api_key(
    authorization: str | None = Header(default=None),
    x_cluster_key: str | None = Header(default=None),
) -> None:
    settings = get_settings()
    expected = settings.api_key
    if expected == "change-me":
        raise HTTPException(status_code=503, detail="API_KEY is not configured")
    prefix = "Bearer "
    if not authorization or not authorization.startswith(prefix):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Bearer token")
    if not hmac.compare_digest(authorization[len(prefix):], expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")
    if settings.require_cluster_key and not (
        x_cluster_key and hmac.compare_digest(x_cluster_key, settings.cluster_key)
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid cluster key")
