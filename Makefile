SHELL := /bin/bash

.PHONY: init models up down doctor smoke test lint

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
