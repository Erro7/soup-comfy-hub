# Soup-Comfy-Hub

Single-GPU orchestration for ComfyUI image/video workflows and Soup fine-tuning, with a FastAPI gateway, Bearer authentication, persistent async tasks, a ModelScope-friendly bootstrap, and a Studio reverse proxy.

## What is implemented

- `POST /v1/images/edits`: three-reference portrait request and title-anchor injection.
- `POST /v1/videos/generations`: sync or async Wan I2V request, MP4/WebM extraction, persistent task state.
- `POST /v1/pipelines/portrait-to-video`: image-to-video chained task.
- `GET /v1/tasks/{task_id}` and authenticated output downloads.
- `POST /v1/soup/train`: isolated subprocess with captured logs.
- One exclusive GPU lock across image, video, and training; ComfyUI `/free` is called at workload transitions.
- Local Gradio status console at `/ui` and a lightweight Studio proxy.
- Chinese AI pose/costume/portrait gallery nodes from `anhao/ai-pose-gallery-zh`.

## Important workflow status

`workflows/wan21_i2v_vertical.json` is an API-format native Wan 2.1 + VideoHelperSuite graph. Its model filename must match the quant you install.

The included multi-reference portrait baseline uses SDXL + InstantID + IPAdapter: face identity is injected through InstantID, the pose image is connected to `image_kps`, and the outfit image is applied through IPAdapter. The Phantom/VACE graph remains an optional template because it is not used by the default portrait-to-video pipeline.

Required image anchors: `LOAD_FACE`, `LOAD_OUTFIT`, `LOAD_POSE`, `PROMPT_POSITIVE`; optional `PROMPT_NEGATIVE`.

Required video anchors: `LOAD_FIRST_FRAME`, `PROMPT_POSITIVE`, `PROMPT_NEGATIVE`, `VIDEO_LATENT_CONFIG`, `VIDEO_OUTPUT`. Add `LOAD_LAST_FRAME` and/or `LOAD_REF_VIDEO` when your selected workflow supports those inputs.

## Notebook quick start

```bash
git clone YOUR_REPOSITORY_URL /mnt/workspace/soup-comfy-hub
cd /mnt/workspace/soup-comfy-hub
make init
cp .env.example .env
# Edit API_KEY, CLUSTER_KEY, and paths in .env
make models
# For a quantized diffusion model:
make up
```

Before `make up`, run `make doctor`. After startup, run `make smoke`.

### Runtime portability

The same runtime supports ModelScope Notebook and NVIDIA Docker. Paths are derived from the checkout by default and can be overridden with `DATA_DIR`, `COMFY_DIR`, `VENV_DIR`, and `PROJECT_DIR`.

```bash
docker compose build
docker compose run --rm runtime bash scripts/download_models.sh
docker compose up -d
```

For a literal first-run download, set `AUTO_DOWNLOAD_MODELS=1`; expect a large download and a long initial startup. Keeping it off is safer for restarts and metered storage.

The root `Dockerfile` is the lightweight ModelScope Studio reverse proxy and listens on `0.0.0.0:7860`. Configure Studio secrets `GATEWAY_PUBLIC_URL`, `API_KEY`, `CLUSTER_KEY`, and `STUDIO_API_KEY`. Studio clients authenticate with `X-API-Key` because ModelScope reserves the standard `Authorization` header.

Cloudflared is optional. It starts only when both `ENABLE_CLOUDFLARED=1` and `CLOUDFLARE_TUNNEL_TOKEN` are set.

### Pose gallery plugin

Bootstrap installs [`anhao/ai-pose-gallery-zh`](https://github.com/anhao/ai-pose-gallery-zh) into ComfyUI `custom_nodes` by default. It provides pose, costume, portrait and three-in-one recipe nodes. The repository includes a large offline image library, so the first clone requires roughly 1.1 GB in addition to model weights. Set `INSTALL_POSE_GALLERY=0` only when building a minimal runtime. The gallery contains optional 18+ reference categories; its own safe mode and source-specific image licenses still apply.

### PyPI mirror selection

`make init` detects the timezone. Mainland-China zones automatically use the
Tsinghua PyPI mirror; other zones use official PyPI. Override it at any time:

```bash
PIP_MIRROR=tsinghua make init  # Tsinghua TUNA
PIP_MIRROR=aliyun make init    # Alibaba Cloud
PIP_MIRROR=pypi make init      # official PyPI
PIP_INDEX_URL=https://example.com/simple make init  # custom index in auto mode
```

For Docker builds, pass `--build-arg PIP_MIRROR=tsinghua`. Mirror selection is
process-local and does not rewrite the user's global `pip.conf`.

The gateway binds to `127.0.0.1:8000`; Cloudflare should be the only public ingress. ComfyUI binds to loopback and is never exposed directly.

## API example

```bash
curl -X POST http://127.0.0.1:8000/v1/videos/generations \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"first_frame_b64":"...","prompt":"slow dolly in","width":720,"height":1280,"num_frames":81,"fps":16,"async_mode":true}'
```

Poll the returned ID:

```bash
curl -H "Authorization: Bearer $API_KEY" http://127.0.0.1:8000/v1/tasks/TASK_ID
```

## Security and operational notes

- Replace both example secrets before startup. Output files require the same Bearer token.
- Studio must receive `GATEWAY_PUBLIC_URL`, `API_KEY`, and `CLUSTER_KEY` as secrets.
- The SQLite task database survives gateway restarts, but an interrupted `running` task is not automatically resumed.
- Base64 raises request memory use; the default per-item limit is 40 MB. Prefer direct object storage for larger production media.
- A 720×1280, 81-frame Wan 14B job may still exceed 24 GB depending on quant, attention backend, and node pack. Start at 480p/33 frames when validating a new quant.
- Do not commit model licenses, private datasets, API keys, tunnel tokens, faces, or generated customer media.

## Development

```bash
python -m pip install -r requirements-dev.txt
python scripts/validate_workflows.py
make test
make lint
```

MIT licensed. Model weights and custom nodes retain their own licenses.
