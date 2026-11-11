import hmac
import os

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import Response, StreamingResponse

UPSTREAM = os.environ.get("GATEWAY_PUBLIC_URL", "").rstrip("/")
CLUSTER_KEY = os.environ.get("CLUSTER_KEY", "")
API_KEY = os.environ.get("API_KEY", "")
STUDIO_API_KEY = os.environ.get("STUDIO_API_KEY", "")
app = FastAPI(title="Soup-Comfy-Hub Studio Proxy")


def _check_cluster():
    if not UPSTREAM or not CLUSTER_KEY or not API_KEY or not STUDIO_API_KEY:
        raise HTTPException(status_code=503, detail="Gateway proxy is not configured")


async def _proxy(request: Request, path: str, x_api_key: str | None):
    _check_cluster()
    if not x_api_key or not hmac.compare_digest(x_api_key, STUDIO_API_KEY):
        raise HTTPException(status_code=401, detail="Invalid X-API-Key")
    headers = {"Authorization": f"Bearer {API_KEY}", "X-Cluster-Key": CLUSTER_KEY}
    body = await request.body()
    async with httpx.AsyncClient(timeout=110) as client:
        response = await client.request(request.method, f"{UPSTREAM}{path}", content=body, headers=headers, params=request.query_params)
    return Response(response.content, status_code=response.status_code, media_type=response.headers.get("content-type"))


@app.api_route("/v1/{path:path}", methods=["GET", "POST"])
async def proxy_v1(path: str, request: Request, x_api_key: str | None = Header(default=None)):
    return await _proxy(request, f"/v1/{path}", x_api_key)


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "upstream_configured": bool(UPSTREAM)}
