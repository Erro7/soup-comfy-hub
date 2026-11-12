# Soup-Comfy-Hub implementation plan

This file is the source of truth for staged delivery. A phase is marked complete only after its acceptance checks pass.

| Phase | Scope | Status | Acceptance |
|---:|---|---|---|
| 1 | Portable paths, platform detection, download helper, standalone cloudflared tool | In progress | Works without root from persistent, user, or project storage; offline regression tests pass |
| 2 | Flattened shell contract for Bash/zsh, OMZ, pip, npm, ModelScope and tools | Pending | One environment and cache contract across supported platforms |
| 3 | Persistent Python/venv lifecycle | Pending | Container restart reuses the same environment without reinstalling |
| 4 | Fast, resilient package and Git source selection | Pending | Mirror changes are explicit, recoverable, and do not corrupt caches |
| 5 | ComfyUI core installation profiles | Pending | Minimal API profile starts without optional template/media packages |
| 6 | ComfyUI image model and custom-node profile | Pending | Image workflow passes an end-to-end smoke test |
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
| 2026-11-12 | 1 | Started: portable tool foundation and tracking established |

## Git policy

Work stays on `main`; no delivery branch is created. The final history rewrite, after all phases are accepted, must use force-with-lease against the verified remote head. No plain force push is permitted.
