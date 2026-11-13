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

All commands resolve the same `DATA_DIR`, `VENV_DIR`, `COMFY_DIR`, cache, logs, and PID file through `scripts/runtime_env.sh`. Every `make init-*` profile initializes the persistent Bash/zsh foundation by default, including Oh My Zsh, histories, pip/npm configuration, package/model caches and standalone tool paths. If zsh is absent, initialization installs it with apt/dnf/yum/apk when root or sudo is available; non-privileged platforms retain the Bash fallback unless `REQUIRE_ZSH=1`. Set `INITIALIZE_SHELL=0` only for non-interactive image builds. Only explicit initialization commands may install or update software.

| Command | Contract |
|---|---|
| `make help` | List the supported command surface. |
| `make init` / `make init-core` | Install the minimal ComfyUI + Gateway core without image/video custom nodes. |
| `make init-image` | Incrementally add InstantID and IPAdapter image nodes. |
| `make init-video` | Incrementally add VideoHelperSuite and GGUF video nodes. |
| `make init-all` | Incrementally install both image and video profiles. |
| `make comfy-profile-status` | Show requested and already-installed profiles. |
| `make venv-init/status/doctor` | Create/reuse, inspect, or validate only the persistent Python environment. |
| `make comfy-deps` | Install the minimal ComfyUI runtime after resolving PyTorch explicitly. |
| `make comfy-deps-status` | Show the active Torch and optional workflow-template policy. |
| `make models` | Download or resume model files; uses the existing venv or Notebook ModelScope client. |
| `make doctor` | Validate the shared venv, API packages, nodes, models, and GPU. |
| `make test-core-runtime` | Run the Step 5 live Gateway-to-ComfyUI acceptance. |
| `make test-image-runtime IMAGE_FACE=... IMAGE_OUTFIT=... IMAGE_POSE=...` | Run one authenticated Step 6 image job and validate returned media. |
| `make up` | Start services only; never installs packages. |
| `make down` | Stop only the recorded supervisor PID; no broad `pkill`. |
| `make restart/status/logs/smoke` | Operate and verify the same service instance and persistent paths. |
| `make shell-init` | Initialize persistent Bash/zsh, package-manager configs and optional Oh My Zsh; venv is not required. |
| `make cloudflared-install` | Install the standalone CLI into writable persistent storage; no root or image rebuild. |
| `make cloudflared-status` | Show the resolved CLI/path/token state without exposing the token. |
| `make shell` | Enter persistent zsh by default and activate the exact same project venv; never installs. |
| `make shell CMD=...` | Run `enter/init/run/status/env/cache/cache-clean/doctor/update/help` through one shell command surface. |
| `make shell CMD=run SHELL_COMMAND='...'` | Run one command with the same managed PATH, package configs, caches and optional venv. |
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

### Environment lifecycle modes

| Mode | Base tools | Persistent/baked roots | Intended use |
|---|---|---|---|
| `build` | Installed by Dockerfile | `/opt/soup-env`, `/opt/venv`, `/opt/ComfyUI` | Reproducible Docker image with zsh, OMZ, tools and runtime baked in |
| `docker` | Existing image plus explicit runtime initialization | Mounted `DATA_DIR` or user/project fallback | Plain or third-party containers that were not built by this project |
| `linux` | Existing host plus apt/dnf/yum/apk when authorized | User/project persistent directories | Generic non-container Linux |
| `modelscope` | Reuses platform Python, Torch and ModelScope | `/mnt/workspace/soup-comfy-data` | ModelScope/DSW notebooks with Alibaba internal mirrors |

`SOUP_ENV_MODE=auto` detects normal runtime environments. `Dockerfile.runtime` explicitly uses `build`, installs system packages first, and bakes the interactive shell and standalone tools under `/opt/soup-env`. Runtime caches and user data remain separate volumes.

### Runtime portability

The same runtime supports ModelScope Notebook and NVIDIA Docker. Notebook mode keeps its environment under the persistent workspace. The GPU container image bakes in Python, ComfyUI, custom nodes, and API dependencies at build time; startup does not install packages. Models and generated data are mounted as separate persistent volumes.

```bash
cp .env.example .env
docker compose build
docker compose run --rm runtime bash scripts/download_models.sh
docker compose up -d
curl -fsS http://127.0.0.1:8000/readyz
```

ComfyUI dependency installation is split from environment creation. Domestic mirrors do not always carry Comfy-published wheels. `comfyui-frontend-package`, `comfyui-embedded-docs`, `comfy-aimdo`, and `comfy-kitchen` are therefore installed with `--no-deps`. On ModelScope/DSW, `PIP_MIRROR=auto` selects the high-speed Alibaba Cloud internal mirror (`mirrors.cloud.aliyuncs.com`). In other China environments, `COMFY_PACKAGE_INDEX_URL=auto` tries the selected mirror, Tencent, USTC, and SJTU before falling back to official PyPI; all ordinary dependencies continue to use the selected mirror. The default path reuses platform-provided PyTorch and filters `torch`, `torchvision`, `torchaudio`, workflow templates, and template media assets out of the ordinary mirror install. This prevents a PyPI mirror from unexpectedly downloading a second CUDA stack. On an image that has no PyTorch, installation must be explicit:

```dotenv
COMFY_TORCH_MODE=install
TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124
```

Workflow templates are optional and use `COMFY_OPTIONAL_INDEX_URL` (official PyPI by default) only when `INSTALL_COMFY_WORKFLOW_TEMPLATES=1`.

The persistent venv is keyed only by its base Python executable, exact Python version, and system-site-packages mode. Changing `PIP_MIRROR` or `PIP_INDEX_URL` does not rebuild it and does not clear the shared pip cache. Set `VENV_REBUILD=1` only for an explicit one-time rebuild.

The flattened shell is independent from ComfyUI and the Python venv. `make shell-init` creates project-scoped pip/npm configuration, persistent histories, cache paths and shared Bash/zsh exports first; when a project venv later exists it is activated automatically. It never writes global pip or npm configuration.

The gateway starts only after ComfyUI answers its health endpoint. `/healthz` checks the gateway process; `/readyz` verifies the usable API-to-ComfyUI path.

For a literal first-run download, set `AUTO_DOWNLOAD_MODELS=1`; expect a large download and a long initial startup. Keeping it off is safer for restarts and metered storage.

The root `Dockerfile` is the lightweight ModelScope Studio reverse proxy and listens on `0.0.0.0:7860`. Configure Studio secrets `GATEWAY_PUBLIC_URL`, `API_KEY`, `CLUSTER_KEY`, and `STUDIO_API_KEY`. Studio clients authenticate with `X-API-Key` because ModelScope reserves the standard `Authorization` header.

Cloudflared is a standalone tool and does not depend on ComfyUI, Python, the venv, zsh, or Oh My Zsh. It is installed by `make init` when `INSTALL_CLOUDFLARED=1`, or explicitly with `make cloudflared-install`. It is not required in the image and does not need root.

For GitHub release binaries, China timezones automatically use the configured single-file accelerator (default `https://ghfast.top/`). Accelerator failure falls back to the original GitHub URL. This policy is intentionally separate from `GITHUB_MIRROR_PREFIX`: file-only proxies are never used for Git clone.

The writable tool path priority is: `TOOLS_HOME` override, `DATA_DIR/tools` (for example ModelScope's persistent workspace), the user's XDG data directory, then the project-local `.tools` fallback. The shared Bash/zsh environment adds its `bin` directory to `PATH`.

The connection uses a remotely managed Cloudflare Tunnel token; hostname routes and origin services are configured in the Cloudflare dashboard.

```dotenv
INSTALL_CLOUDFLARED=1
ENABLE_CLOUDFLARED=1
CLOUDFLARE_TUNNEL_TOKEN=your-token
CLOUDFLARE_PUBLIC_URL=https://comfy.example.com
```

```bash
make cloudflared-install
make cloudflared-status
make tunnel        # foreground tunnel only
make up            # supervise ComfyUI, API and tunnel together
```

On a normal Linux host with systemd, `make tunnel-service-install` delegates to Cloudflare's official `cloudflared service install <TOKEN>` flow and enables the service. ModelScope/DSW containers do not provide a persistent systemd instance, so use the project supervisor through `make up/down/status` there.

The gateway binds to `127.0.0.1:8000`; Cloudflare should be the only public ingress. ComfyUI binds to loopback and is never exposed directly.

## ComfyUI installation profiles

The default is API-first and intentionally small:

```bash
make init-core
make test-core-runtime
```

Image and video support are incremental and keep the same venv, ComfyUI checkout, caches, API, and persistent data:

```bash
make init-image
COMFY_PROFILE=image make comfy-profile-status
COMFY_PROFILE=image make doctor-image

make init-video
COMFY_PROFILE=video make comfy-profile-status
COMFY_PROFILE=video MODEL_PROFILE=video make doctor
```

Profile installation never downloads model weights. Model downloads remain separate and resumable.

After downloading the image profile, run the real image-chain acceptance with three local reference images:

```bash
make down
make models-image
make doctor-image
make test-image-runtime \
  IMAGE_FACE=/path/to/clear-face.png \
  IMAGE_OUTFIT=/path/to/outfit-reference.png \
  IMAGE_POSE=/path/to/pose-reference.png
```

The command starts temporary services only when needed, submits an authenticated `POST /v1/images/edits`, validates the returned image signature, and writes `step6-image-test.png` under the persistent task output directory. Set `IMAGE_OUTPUT=/path/result.png` or `IMAGE_PROMPT='...'` to override those defaults. If services were already running, they are reused and left running; restart them after `make init-image` so newly installed nodes are loaded.

`make test-core-runtime` is the Step 5 acceptance test. It validates the core installation, starts ComfyUI and Gateway only when needed, checks local readiness plus required OpenAPI routes, and stops only services started by the test. Existing services are reused and left running.

## Selective model downloads

Model downloads are resumable and prefer the ModelScope library preinstalled by supported Notebook images. The downloader does not install ModelScope into the project venv unless `INSTALL_MODELSCOPE_CLIENT=1` is explicitly set.

The image profile is declared in `config/model-profiles/image.tsv`. That manifest is shared by the downloader, Doctor, and workflow validator, so model filenames and ComfyUI paths cannot silently drift.

```bash
make init-image
make models-image
make validate-workflows
make doctor-image

make models-video
MODEL_PROFILE=video make doctor

make models                 # image + video
MODEL_PROFILE=all make doctor
```

Download one exact file from any ModelScope repository:

```bash
make models-custom \
  MODEL_ID=organization/repository \
  MODEL_FILE=path/to/model.safetensors \
  MODEL_DIR=diffusion_models \
  MODEL_REVISION=master

MODEL_PROFILE=custom \
MODEL_FILE=path/to/model.safetensors \
MODEL_DIR=diffusion_models \
make doctor
```

`MODEL_DIR` is relative to `ComfyUI/models`, for example `checkpoints`, `diffusion_models`, `vae`, `loras`, or `controlnet`. Custom downloads reject absolute paths, parent traversal, and glob patterns.

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


## Staged implementation

Progress, phase acceptance criteria, and the final Git policy are tracked in [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md).
