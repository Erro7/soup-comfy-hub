# Soup-Comfy-Hub implementation plan

This file is the source of truth for staged delivery. A phase is marked complete only after its acceptance checks pass.

| Phase | Scope | Status | Acceptance |
|---:|---|---|---|
| 1 | Portable paths, platform detection, download helper, standalone cloudflared tool | Complete | Works without root from persistent, user, or project storage; offline regression tests pass |
| 2 | Flattened shell contract for Bash/zsh, OMZ, pip, npm, ModelScope and tools | Complete | One environment and cache contract across supported platforms |
| 3 | Persistent Python/venv lifecycle | Complete | Container restart reuses the same environment without reinstalling |
| 4 | Fast, resilient package and Git source selection | Complete | Mirror changes are explicit, recoverable, and do not corrupt caches |
| 5 | ComfyUI core installation profiles | In progress | Minimal API profile starts without optional template/media packages |
| 6 | ComfyUI image model and custom-node profile | In progress | Image workflow passes an end-to-end smoke test |
| 7 | ComfyUI video model and custom-node profile | Pending | Video workflow passes an end-to-end smoke test |
| 8 | API gateway core | Pending | Authenticated API can submit, poll, and retrieve ComfyUI jobs |
| 9 | Service supervision and observability | Pending | Start, stop, status, logs, readiness and URLs are deterministic |
| 10 | Remote access with token-managed Cloudflare Tunnel | Pending | Tunnel targets the local API/Comfy origins without exposing tokens |
| 11 | Model download profiles | Pending | Exact image/video/LoRA files download resumably by profile |
| 12 | Image LoRA training profile | Pending | Isolated training environment and a reproducible smoke run |
| 13 | Video LoRA training profile | Pending | Isolated training environment and a reproducible smoke run |
| 14 | Cross-platform regression matrix | Pending | Generic Linux, Docker and ModelScope path/lifecycle tests pass |
| 15 | Documentation, migration and release history normalization | Pending | Upgrade guide complete; final main update uses force-with-lease only |

## Phase 1 decisions

- No CLI is required to be baked into an image.
- Runtime tools live in a writable persistent directory.
- Path priority is: explicit override, project data directory, user data directory, project-local fallback.
- cloudflared is independent of ComfyUI, Python, the project venv, zsh and Oh My Zsh.
- Cloudflare uses a remotely managed Tunnel token. Dashboard-managed ingress remains the authority.
- Existing `make tunnel-*` commands remain compatibility aliases.

## Delivery log

| Date | Phase | Result |
|---|---:|---|
| 2026-11-12 | 6 | In progress: image model manifest, preinstalled ModelScope selection, manifest-driven download/Doctor checks and workflow filename validation implemented; GPU image generation remains to be accepted |\n| 2026-11-12 | 5 | In progress: core/image/video/all installers, cumulative profile state, profile-aware doctor and startup preflight implemented; real ComfyUI readiness remains to be accepted on the GPU platform |\n| 2026-11-12 | 4 | Complete: cache-preserving mirror changes, direct Git fallback, explicit PyTorch source, official optional-package fallback, and minimal dependency renderer; Phase 5 core profile started |\n| 2026-11-12 | 3 | Complete: standalone venv lifecycle, base-Python compatibility state, restart reuse, explicit rebuild control, and pip-index/cache separation |\n| 2026-11-12 | 2 | Complete: venv-independent Bash/zsh initialization, project-scoped pip/npm configs, persistent package/model caches, optional OMZ, managed command execution and offline regression |\n| 2026-11-12 | 1 | Complete: path/platform/download libraries, standalone token-based cloudflared CLI, Make compatibility aliases, shared-shell PATH integration, and offline regression added |

## Phase 1 verification

- `bash -n` passed for all new and modified shell entrypoints.
- `tests/test_tools.sh` passed with a fake cloudflared binary and no network access.
- Status output was verified not to reveal the configured Tunnel token.
- The run contract was verified as `tunnel --no-autoupdate run --token <hidden>`.

## Phase 2 verification

- Shell initialization passed with no project venv present.
- pip and npm configuration was verified under the persistent shell directory.
- Managed command execution inherited the resolved tool environment.
- Phase 1 and Phase 2 offline shell regressions passed together.

## Phase 3 verification

- A temporary persistent venv was created and validated without installing project packages.
- Reinitialization after changing the package index preserved a marker inside the venv.
- Package-index switching was verified not to purge the pip cache.
- Phase 1–3 shell regressions passed together.

## Phase 4 verification

- Mirror selection regressions passed for Tsinghua, Aliyun, official PyPI and a custom index.
- Changing indexes preserved both the persistent venv and pip cache.
- Minimal ComfyUI requirements removed implicit Torch/CUDA and workflow-template media downloads.
- Docker runtime configuration declares its PyTorch source explicitly.
- Phase 1–4 offline regressions passed together.

## Phase 5 implementation verification

- Core profile resolved to zero optional custom nodes.
- Image, video and all profile node matrices passed offline regression.
- Profile installation state was verified cumulative across later upgrades.
- Doctor defaults to the core profile and no model-weight checks.
- Startup now refuses an uninitialized runtime with an actionable `make init-core` message.
- Final phase acceptance still requires `make up && make smoke` on the target GPU platform.

## Phase 6 implementation verification

- The image manifest provides every model filename referenced by the portrait workflow.
- Manifest paths were checked for traversal, duplicate targets and invalid entries.
- Download and Doctor use the same manifest instead of duplicate hard-coded paths.
- The downloader defaults to the ModelScope client preinstalled by the platform.
- Workflow anchors and the image model contract passed offline validation.
- Final phase acceptance requires one successful authenticated image API job on the GPU platform.

## Git policy

Work stays on `main`; no delivery branch is created. The final history rewrite, after all phases are accepted, must use force-with-lease against the verified remote head. No plain force push is permitted.
