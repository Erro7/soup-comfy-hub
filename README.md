# Soup-Comfy-Hub

API-first single-GPU runtime for ComfyUI image/video workflows. ComfyUI and the FastAPI gateway form the required core; Soup fine-tuning and Cloudflared are optional.

## What is implemented

- `POST /v1/images/edits`: three-reference portrait request and title-anchor injection.
- `POST /v1/videos/generations`: sync or async Wan I2V request, MP4/WebM extraction, persistent task state.
- `POST /v1/pipelines/portrait-to-video`: image-to-video chained task.
- `GET /v1/tasks/{task_id}` and authenticated output downloads.
- Optional `POST /v1/soup/train`: registered only when `ENABLE_SOUP=1` and Soup was installed.
- One exclusive GPU lock across image, video, and training; ComfyUI `/free` is called at workload transitions.
- Optional Gradio status console at `/ui`; disabled in the default API runtime.
- Optional Chinese pose gallery; disabled by default because its offline assets are large.

## Important workflow status

`workflows/wan21_i2v_vertical.json` is an API-format native Wan 2.1 + VideoHelperSuite graph. Its model filename must match the quant you install.

The included multi-reference portrait baseline uses SDXL + InstantID + IPAdapter: face identity is injected through InstantID, the pose image is connected to `image_kps`, and the outfit image is applied through IPAdapter. The Phantom/VACE graph remains an optional template because it is not used by the default portrait-to-video pipeline.

Required image anchors: `LOAD_FACE`, `LOAD_OUTFIT`, `LOAD_POSE`, `PROMPT_POSITIVE`; optional `PROMPT_NEGATIVE`.

Required video anchors: `LOAD_FIRST_FRAME`, `PROMPT_POSITIVE`, `PROMPT_NEGATIVE`, `VIDEO_LATENT_CONFIG`, `VIDEO_OUTPUT`. Add `LOAD_LAST_FRAME` and/or `LOAD_REF_VIDEO` when your selected workflow supports those inputs.

## Make command contract

All commands resolve the same `DATA_DIR`, `VENV_DIR`, `COMFY_DIR`, cache, logs, and PID file through `scripts/runtime_env.sh`. Only explicit initialization commands may install or update software.

| Command | Contract |
|---|---|
| `make help` | List the supported command surface. |
| `make init` | One-time/resumable persistent venv, ComfyUI, node, and API dependency setup. |
| `make models` | Download or resume model files; uses the existing venv or Notebook ModelScope client. |
| `make doctor` | Validate the shared venv, API packages, nodes, models, and GPU. |
| `make up` | Start services only; never installs packages. |
| `make down` | Stop only the recorded supervisor PID; no broad `pkill`. |
| `make restart/status/logs/smoke` | Operate and verify the same service instance and persistent paths. |
| `make shell-init` | Explicitly install/configure persistent zsh and Oh My Zsh. |
| `make shell` | Enter that shell and activate the exact same project venv; never installs. |
| `make shell CMD=...` | Run `enter/init/status/env/update/help` through one shell command surface. |
| `make test/lint` | Run developer tools through the shared project venv. |

## Notebook quick start

```bash
git clone YOUR_REPOSITORY_URL /mnt/workspace/soup-comfy-hub
cd /mnt/workspace/soup-comfy-hub
cp .env.example .env
# Edit API_KEY and paths once.
make init      # one-time persistent environment
make models    # one-time/resumable model download
make doctor
make up        # every later container start
```

Before `make up`, run `make doctor`. After startup, run `make smoke`.

### Runtime portability

The same runtime supports ModelScope Notebook and NVIDIA Docker. Notebook mode keeps its environment under the persistent workspace. The GPU container image bakes in Python, ComfyUI, custom nodes, and API dependencies at build time; startup does not install packages. Models and generated data are mounted as separate persistent volumes.

```bash
cp .env.example .env
docker compose build
docker compose run --rm runtime bash scripts/download_models.sh
docker compose up -d
curl -fsS http://127.0.0.1:8000/readyz
```

The gateway starts only after ComfyUI answers its health endpoint. `/healthz` checks the gateway process; `/readyz` verifies the usable API-to-ComfyUI path.

For a literal first-run download, set `AUTO_DOWNLOAD_MODELS=1`; expect a large download and a long initial startup. Keeping it off is safer for restarts and metered storage.

The root `Dockerfile` is the lightweight ModelScope Studio reverse proxy and listens on `0.0.0.0:7860`. Configure Studio secrets `GATEWAY_PUBLIC_URL`, `API_KEY`, `CLUSTER_KEY`, and `STUDIO_API_KEY`. Studio clients authenticate with `X-API-Key` because ModelScope reserves the standard `Authorization` header.

Cloudflared is optional. It starts only when both `ENABLE_CLOUDFLARED=1` and `CLOUDFLARE_TUNNEL_TOKEN` are set.

### Persistent API runtime

The default installation contains only ComfyUI and FastAPI dependencies. The Notebook venv, ComfyUI checkout, pip cache, models, task database, and outputs live under `/mnt/workspace/soup-comfy-data`. Run `make init` once; subsequent container starts use `make up` and never install packages.

### Persistent shell

The shell environment is separate from the Python venv but stored under the same persistent data root. It keeps Oh My Zsh, `.zshrc`, history, and the managed environment across Notebook restarts, and automatically activates the project venv.

```bash
make shell-init              # one-time OMZ/config initialization
make shell                   # enter zsh with the venv active
make shell-status            # inspect runtime and shell persistence
make shell-env               # print resolved paths
make shell-update            # explicitly update OMZ
make shell CMD=status        # unified secondary-command form
make shell-help
```

Docker images include the `zsh` binary; mutable shell state remains in the mounted `/data/shell` directory. On a Notebook image without zsh, `make shell-init` installs the small system package when running as root.

### ComfyUI API dependency mode

The default bootstrap omits `comfyui-workflow-templates` and its large media-asset packages. They only populate the Web UI Templates browser and are not required for the bundled API-format workflows. Set `INSTALL_COMFY_WORKFLOW_TEMPLATES=1` only when the complete ComfyUI template gallery is required and the selected PyPI index contains every asset package.

### Optional Gradio UI

Gradio is not required by any REST endpoint. Enable it only when needed with `INSTALL_GRADIO_UI=1 make init` and `ENABLE_GRADIO_UI=1`.

### Optional Soup

Soup is disabled by default and is not needed for image or video APIs. In Notebook mode, install and enable it with `INSTALL_SOUP=1 make init` plus `ENABLE_SOUP=1`. For Docker, set both values before `docker compose build`; enabling Soup at runtime without building it into the image will fail `make doctor`.

### Pose gallery plugin

Bootstrap installs [`anhao/ai-pose-gallery-zh`](https://github.com/anhao/ai-pose-gallery-zh) only when `INSTALL_POSE_GALLERY=1`. It provides pose, costume, portrait and three-in-one recipe nodes. The repository includes a large offline image library, so the first clone requires roughly 1.1 GB in addition to model weights. Keep `INSTALL_POSE_GALLERY=0` for the minimal API runtime. The gallery contains optional 18+ reference categories; its own safe mode and source-specific image licenses still apply.

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
