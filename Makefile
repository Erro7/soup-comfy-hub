SHELL := /bin/bash

.PHONY: init models up down doctor smoke test lint shell shell-init shell-status shell-env shell-update shell-help

init:
	bash scripts/bootstrap.sh

models:
	bash scripts/download_models.sh

up:
	bash scripts/start_services.sh

doctor:
	bash scripts/doctor.sh

smoke:
	bash scripts/smoke_test.sh

down:
	@if [ -f /mnt/workspace/soup-comfy-hub/logs/services.pid ]; then kill "$$(cat /mnt/workspace/soup-comfy-hub/logs/services.pid)" 2>/dev/null || true; fi
	@pkill -f 'uvicorn gateway.main:app' 2>/dev/null || true
	@pkill -f 'ComfyUI/main.py' 2>/dev/null || true

test:
	python -m pytest -q

lint:
	python -m ruff check gateway studio_frontend tests

# Persistent developer shell. Use "make shell CMD=status" for the unified
# secondary-command form, or the convenience targets below.
CMD ?= enter

shell:
	bash scripts/shell.sh "$(CMD)"

shell-init:
	bash scripts/shell.sh init

shell-status:
	bash scripts/shell.sh status

shell-env:
	bash scripts/shell.sh env

shell-update:
	bash scripts/shell.sh update

shell-help:
	bash scripts/shell.sh help
