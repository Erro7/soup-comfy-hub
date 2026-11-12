SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help init models doctor up down restart status logs smoke test lint \
        shell shell-init shell-status shell-env shell-update shell-help

CMD ?= enter

help:
	@echo "Soup-Comfy-Hub commands"
	@echo
	@echo "  make init          One-time persistent venv, ComfyUI and node setup"
	@echo "  make models        Download/resume models into persistent storage"
	@echo "  make doctor        Validate venv, ComfyUI, nodes, models and GPU"
	@echo "  make up            Start ComfyUI and API in the foreground"
	@echo "  make down          Stop the exact service supervisor from its PID file"
	@echo "  make restart       Stop, then start ComfyUI and API"
	@echo "  make status        Show service state and persistent paths"
	@echo "  make logs          Follow ComfyUI and gateway logs"
	@echo "  make smoke         Test Gateway -> ComfyUI readiness"
	@echo
	@echo "  make shell         Enter persistent zsh using the same project venv"
	@echo "  make shell-init    Explicitly initialize zsh and Oh My Zsh"
	@echo "  make shell-status  Inspect shared venv and shell state"
	@echo "  make shell-env     Print sourceable resolved environment exports"
	@echo "  make shell-update  Explicitly update Oh My Zsh"
	@echo "  make shell CMD=... Unified shell subcommand: enter/init/status/env/update/help"
	@echo
	@echo "  make test          Run tests in the project venv"
	@echo "  make lint          Run Ruff in the project venv"

init:
	bash scripts/bootstrap.sh

models:
	bash scripts/download_models.sh

doctor:
	bash scripts/doctor.sh

up:
	bash scripts/start_services.sh

down:
	bash scripts/services.sh stop

restart:
	bash scripts/services.sh stop
	bash scripts/start_services.sh

status:
	bash scripts/shell.sh status
	bash scripts/services.sh status

logs:
	bash scripts/services.sh logs

smoke:
	bash scripts/smoke_test.sh

test:
	bash scripts/venv_exec.sh python -m pytest -q

lint:
	bash scripts/venv_exec.sh python -m ruff check gateway studio_frontend tests

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
