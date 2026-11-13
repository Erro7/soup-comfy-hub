# Soup-Comfy-Hub implementation plan

This file is the source of truth for staged delivery. A phase is marked complete only after its acceptance checks pass.

| Phase | Scope | Status | Acceptance |
|---:|---|---|---|
| 1 | Portable paths, platform detection, download helper, standalone cloudflared tool | Complete | Works without root from persistent, user, or project storage; offline regression tests pass |
| 2 | Flattened shell contract for Bash/zsh, OMZ, pip, npm, ModelScope and tools | Complete | One environment and cache contract across supported platforms |
| 3 | Persistent Python/venv lifecycle | Complete | Container restart reuses the same environment without reinstalling |
| 4 | Fast, resilient package and Git source selection | Complete | Mirror changes are explicit, recoverable, and do not corrupt caches |
| 5 | ComfyUI core installation profiles | Complete | Minimal API profile starts without optional template/media packages |
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

| 2026-11-12 | 6 | Fixed: antelopev2 now uses the official checksummed archive with cached, safe, idempotent extraction instead of an incomplete ModelScope mirror |
| 2026-11-12 | 2 | Fixed: ModelScope/plain-container zsh is now a persistent relocatable tool, so container restart does not trigger apt reinstallation |

| Date | Phase | Result |
|---|---:|---|
| 2026-11-13 | 6 | Fixed: directory-based ModelScope assets now use resumable full snapshots; antelopev2 is located, ONNX-validated and linked into the InstantID layout |\n| 2026-11-13 | 6 | Test ready: `make test-image-runtime` validates image Doctor, required ComfyUI node classes, authenticated Gateway submission and generated image output |\n| 2026-11-12 | 6 | In progress: image model manifest, preinstalled ModelScope selection, manifest-driven download/Doctor checks and workflow filename validation implemented; GPU image generation remains to be accepted |\n| 2026-11-13 | 5 | Complete: target ModelScope GPU acceptance reported `Step 5 core runtime acceptance: PASS`; Gateway-to-ComfyUI readiness and API route contract passed |\n| 2026-11-12 | 5 | Test ready: `make test-core-runtime` performs profile Doctor, temporary service lifecycle, readiness and OpenAPI route acceptance without stopping pre-existing services |\n| 2026-11-12 | 5 | In progress: core/image/video/all installers, cumulative profile state, profile-aware doctor and startup preflight implemented; real ComfyUI readiness remains to be accepted on the GPU platform |\n| 2026-11-12 | 4 | Optimized: ModelScope/DSW now selects the Alibaba Cloud internal PyPI mirror before all public mirrors |\n| 2026-11-12 | 4 | Optimized: China installs try Tsinghua, Tencent, USTC and SJTU for new Comfy wheels before the official PyPI fallback |\n| 2026-11-12 | 4 | Fixed: Comfy-published wheels bypass incomplete domestic mirrors with no-deps official-index installs while ordinary dependencies remain mirrored |\n| 2026-11-12 | 4 | Refined: GitHub single-file downloads use a timezone-aware CN accelerator with automatic direct fallback; Git clone remains isolated from file-only proxies |\n| 2026-11-12 | 4 | Complete: cache-preserving mirror changes, direct Git fallback, explicit PyTorch source, official optional-package fallback, and minimal dependency renderer; Phase 5 core profile started |\n| 2026-11-12 | 3 | Complete: standalone venv lifecycle, base-Python compatibility state, restart reuse, explicit rebuild control, and pip-index/cache separation |\n| 2026-11-12 | 2 | Refined: environment lifecycle now separates image-baked build, generic Docker/Linux runtime initialization, and ModelScope-specific persistence/reuse |\n| 2026-11-12 | 2 | Fixed: missing zsh is installed through the detected system package manager when privileges allow, then persistent OMZ initialization continues |\n| 2026-11-12 | 2 | Refined: every runtime init profile now initializes the persistent Bash/zsh, OMZ, package-config and cache foundation; disposable Docker builds opt out |\n| 2026-11-12 | 2 | Complete: venv-independent Bash/zsh initialization, project-scoped pip/npm configs, persistent package/model caches, optional OMZ, managed command execution and offline regression |\n| 2026-11-12 | 1 | Complete: path/platform/download libraries, standalone token-based cloudflared CLI, Make compatibility aliases, shared-shell PATH integration, and offline regression added |

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

- Comfy-owned packages were verified to fail over from a missing Tsinghua version to Tencent with `--no-deps`, while NumPy/aiohttp and other dependencies stayed on the selected mirror.
- Mirror selection regressions passed for Tsinghua, Aliyun, official PyPI and a custom index.
- Changing indexes preserved both the persistent venv and pip cache.
- Minimal ComfyUI requirements removed implicit Torch/CUDA and workflow-template media downloads.
- Docker runtime configuration declares its PyTorch source explicitly.
- China-timezone GitHub file acceleration and direct fallback passed with a simulated failed accelerator.
- Phase 1–4 offline regressions passed together.

## Phase 5 implementation verification

- Core profile resolved to zero optional custom nodes.
- Image, video and all profile node matrices passed offline regression.
- Profile installation state was verified cumulative across later upgrades.
- Doctor defaults to the core profile and no model-weight checks.
- Startup now refuses an uninitialized runtime with an actionable `make init-core` message.
- Target ModelScope GPU acceptance passed: `make test-core-runtime` reported `Step 5 core runtime acceptance: PASS`.

## Phase 6 implementation verification

- The image manifest provides every model filename referenced by the portrait workflow.
- Manifest paths were checked for traversal, duplicate targets and invalid entries.
- Download and Doctor use the same manifest instead of duplicate hard-coded paths.
- The downloader defaults to the ModelScope client preinstalled by the platform.
- Workflow anchors and the image model contract passed offline validation.
- `make test-image-runtime` now checks image Doctor, workflow validation, required live node classes, authenticated API submission and returned media signature.
- Final phase acceptance requires this command to report `Step 6 image runtime acceptance: PASS` on the GPU platform.

## Environment lifecycle decision

- Docker builds bake zsh, OMZ, standalone CLIs, the venv and ComfyUI into image-owned paths.
- An already-built/plain container initializes only missing tools into writable persistent paths.
- Generic Linux uses user/project storage and system packages only when authorized.
- ModelScope uses `/mnt/workspace`, preinstalled Python/Torch/ModelScope, and Alibaba internal mirrors.
- Model weights, generated output and runtime data stay outside immutable image layers.

## Git policy

Work stays on `main`; no delivery branch is created. The final history rewrite, after all phases are accepted, must use force-with-lease against the verified remote head. No plain force push is permitted.
