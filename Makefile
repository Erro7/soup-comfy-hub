SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help init models models-image models-video models-custom doctor up down restart status logs smoke test test-tools test-shell lint \
        shell shell-init shell-status shell-env shell-cache shell-cache-clean \
        shell-doctor shell-update shell-help tools-status cloudflared-install cloudflared-status tunnel tunnel-init tunnel-status tunnel-service-install tunnel-service-start tunnel-service-stop tunnel-service-restart tunnel-service-status tunnel-service-uninstall

CMD ?= enter
MODEL_PROFILE ?= all
SHELL_KIND ?= zsh
CACHE_KIND ?=
SHELL_COMMAND ?=

help:
	@echo "Soup-Comfy-Hub commands"
	@echo
	@echo "  make init          One-time persistent venv, ComfyUI and node setup"
	@echo "  make models        Download/resume all model profiles"
	@echo "  make models-image  Download only SDXL/InstantID/IPAdapter models"
	@echo "  make models-video  Download only Wan video models"
	@echo "  make models-custom MODEL_ID=... MODEL_FILE=... MODEL_DIR=..."
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
	@echo "  make shell-cache   Show persistent package cache sizes"
	@echo "  make shell-cache-clean CACHE_KIND=pip   Clean one explicit cache"
	@echo "  make shell-doctor  Validate Bash/zsh, venv, paths and permissions"
	@echo "  make shell-update  Explicitly update Oh My Zsh"
	@echo "  make shell SHELL_KIND=bash|zsh"
	@echo "  make shell CMD=... Unified subcommand: enter/init/run/status/env/cache/cache-clean/doctor/update/help"
	@echo
	@echo "  make tools-status  Show standalone tool locations"
	@echo "  make cloudflared-install   Install cloudflared without root into persistent storage"
	@echo "  make cloudflared-status    Inspect the standalone CLI and token settings"
	@echo "  make tunnel-init   Compatibility alias for cloudflared-install"
	@echo "  make tunnel        Run the remote-managed tunnel with CLOUDFLARE_TUNNEL_TOKEN"
	@echo "  make tunnel-status Inspect CLI installation, token and runtime settings"
	@echo "  make tunnel-service-install   Install/start the official token-based systemd service"
	@echo "  make tunnel-service-status    Inspect the systemd service"
	@echo
	@echo "  make test          Run tests in the project venv"
	@echo "  make lint          Run Ruff in the project venv"

init:
	bash scripts/bootstrap.sh

models:
	MODEL_PROFILE="$(MODEL_PROFILE)" bash scripts/download_models.sh

models-image:
	MODEL_PROFILE=image bash scripts/download_models.sh

models-video:
	MODEL_PROFILE=video bash scripts/download_models.sh

models-custom:
	MODEL_PROFILE=custom MODEL_ID="$(MODEL_ID)" MODEL_FILE="$(MODEL_FILE)" MODEL_DIR="$(MODEL_DIR)" MODEL_REVISION="$(MODEL_REVISION)" bash scripts/download_models.sh

doctor:
	MODEL_PROFILE="$(MODEL_PROFILE)" MODEL_FILE="$(MODEL_FILE)" MODEL_DIR="$(MODEL_DIR)" bash scripts/doctor.sh

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
	bash tests/test_tools.sh
	bash tests/test_shell_env.sh

test-tools:
	bash tests/test_tools.sh

test-shell:
	bash tests/test_shell_env.sh

lint:
	bash scripts/venv_exec.sh python -m ruff check gateway studio_frontend tests

shell:
	SHELL_KIND="$(SHELL_KIND)" CACHE_KIND="$(CACHE_KIND)" SHELL_COMMAND="$(SHELL_COMMAND)" bash scripts/shell.sh "$(CMD)"

shell-init:
	SHELL_KIND="$(SHELL_KIND)" bash scripts/shell.sh init

shell-status:
	bash scripts/shell.sh status

shell-env:
	@bash scripts/shell.sh env

shell-cache:
	@bash scripts/shell.sh cache

shell-cache-clean:
	@CACHE_KIND="$(CACHE_KIND)" bash scripts/shell.sh cache-clean

shell-doctor:
	@bash scripts/shell.sh doctor

shell-update:
	bash scripts/shell.sh update

shell-help:
	bash scripts/shell.sh help

tools-status:
	@bash scripts/tools/cloudflared.sh status

cloudflared-install:
	bash scripts/tools/cloudflared.sh install

cloudflared-status:
	@bash scripts/tools/cloudflared.sh status

tunnel-init: cloudflared-install

tunnel:
	bash scripts/tunnel.sh run


tunnel-status:
	bash scripts/tunnel.sh status

tunnel-service-install:
	bash scripts/tunnel.sh service-install

tunnel-service-start:
	bash scripts/tunnel.sh service-start

tunnel-service-stop:
	bash scripts/tunnel.sh service-stop

tunnel-service-restart:
	bash scripts/tunnel.sh service-restart

tunnel-service-status:
	bash scripts/tunnel.sh service-status

tunnel-service-uninstall:
	bash scripts/tunnel.sh service-uninstall
