SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help init models models-image models-video models-custom doctor up down restart status logs smoke test lint \
        shell shell-init shell-status shell-env shell-cache shell-cache-clean \
        shell-doctor shell-update shell-help tunnel tunnel-init tunnel-login tunnel-create tunnel-setup tunnel-route tunnel-validate tunnel-list tunnel-info tunnel-status tunnel-service-install tunnel-service-start tunnel-service-stop tunnel-service-restart tunnel-service-status tunnel-service-uninstall

CMD ?= enter
MODEL_PROFILE ?= all
SHELL_KIND ?= zsh
CACHE_KIND ?=

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
	@echo "  make shell CMD=... Unified subcommand: enter/init/status/env/cache/cache-clean/doctor/update/help"
	@echo
	@echo "  make tunnel-init   Install cloudflared into persistent shell storage"
	@echo "  make tunnel-login  Authenticate the Cloudflare CLI and persist cert.pem"
	@echo "  make tunnel-setup TUNNEL_NAME=... TUNNEL_HOSTNAME=... TUNNEL_SERVICE=..."
	@echo "                     Create tunnel, config.yml and DNS route through the CLI"
	@echo "  make tunnel        Validate and run the locally managed tunnel"
	@echo "  make tunnel-status Inspect CLI, certificate, config and tunnels"
	@echo "  make tunnel-service-install   Install/start the official systemd service"
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

lint:
	bash scripts/venv_exec.sh python -m ruff check gateway studio_frontend tests

shell:
	SHELL_KIND="$(SHELL_KIND)" CACHE_KIND="$(CACHE_KIND)" bash scripts/shell.sh "$(CMD)"

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

tunnel-init:
	bash scripts/tunnel.sh init

tunnel-login:
	bash scripts/tunnel.sh login

tunnel-create:
	CLOUDFLARE_TUNNEL_NAME="$(TUNNEL_NAME)" bash scripts/tunnel.sh create

tunnel-setup:
	CLOUDFLARE_TUNNEL_NAME="$(TUNNEL_NAME)" CLOUDFLARE_TUNNEL_HOSTNAME="$(TUNNEL_HOSTNAME)" CLOUDFLARE_TUNNEL_SERVICE="$(TUNNEL_SERVICE)" bash scripts/tunnel.sh setup

tunnel-route:
	CLOUDFLARE_TUNNEL_NAME="$(TUNNEL_NAME)" CLOUDFLARE_TUNNEL_HOSTNAME="$(TUNNEL_HOSTNAME)" bash scripts/tunnel.sh route

tunnel-validate:
	bash scripts/tunnel.sh validate

tunnel:
	bash scripts/tunnel.sh run

tunnel-list:
	bash scripts/tunnel.sh list

tunnel-info:
	CLOUDFLARE_TUNNEL_NAME="$(TUNNEL_NAME)" bash scripts/tunnel.sh info

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
