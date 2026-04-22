DOCKER_BINARY := docker-compose -f docker/docker-compose.yml --env-file .env

.PHONY: help start stop restart build dev shell logs status
.PHONY: test-device test-logs test-stop test-clean
.PHONY: setup sudo-setup non-sudo-setup
.PHONY: tailscale-status tailscale-up tailscale-down
.PHONY: logs-prod-nodejs logs-prod-traefik logs-prod-tailscale logs-prod-all
.PHONY: restart-prod-nodejs restart-prod-traefik restart-prod-tailscale restart-prod-all
.PHONY: stop-prod-all status-prod update-prod enable-auth disable-auth show-auth-status

# Default target
help:
	@echo "IoT Pilot Commands"
	@echo "=================="
	@echo ""
	@echo "🚀 Development:"
	@echo "  start          - Start all services"
	@echo "  stop           - Stop all services"
	@echo "  restart        - Restart all services"
	@echo "  build          - Build containers"
	@echo "  dev            - Start in development mode"
	@echo "  shell          - Open shell in main container"
	@echo "  logs           - Show app logs"
	@echo "  status         - Show service status"
	@echo ""
	@echo "🧪 Test Device:"
	@echo "  test-device    - Start test IoT device"
	@echo "  test-logs      - Show test device logs"
	@echo "  test-stop      - Stop test device"
	@echo "  test-clean     - Clean test resources"
	@echo ""
	@echo "🏭 Production (Raspberry Pi):"
	@echo "  logs-prod-nodejs     - Show Node.js logs"
	@echo "  logs-prod-traefik    - Show Traefik logs"
	@echo "  logs-prod-tailscale  - Show Tailscale logs"
	@echo "  logs-prod-all        - Show all service logs"
	@echo "  restart-prod-nodejs  - Restart Node.js service"
	@echo "  restart-prod-traefik - Restart Traefik service"
	@echo "  restart-prod-tailscale - Restart Tailscale service"
	@echo "  restart-prod-all     - Restart all services"
	@echo "  stop-prod-all        - Stop all services"
	@echo "  status-prod          - Show production status"
	@echo "  update-prod          - Pull latest code from main and restart iotpilot"
	@echo "  enable-auth          - Turn AUTH_ENABLED on (generates SESSION_SECRET if missing)"
	@echo "  disable-auth         - Turn AUTH_ENABLED off"
	@echo "  show-auth-status     - Print current auth configuration"
	@echo ""
	@echo "🔧 Setup:"
	@echo "  setup          - Setup certificates and hosts"
	@echo "  tailscale-status - Show Tailscale status"

# Development commands
start:
	@$(DOCKER_BINARY) up -d --remove-orphans

stop:
	@$(DOCKER_BINARY) down --remove-orphans

restart: stop start

build:
	@$(DOCKER_BINARY) build --no-cache

dev: stop
	@$(DOCKER_BINARY) up

shell:
	@$(DOCKER_BINARY) exec iotpilot bash

logs:
	@$(DOCKER_BINARY) logs -f iotpilot

status:
	@$(DOCKER_BINARY) ps

# Test device commands
test-device:
	@echo "🧪 Starting test IoT device..."
	@$(DOCKER_BINARY) --profile test up -d test-device
	@echo "✅ Test device started!"
	@echo "📋 Monitor: make test-logs"

test-logs:
	@$(DOCKER_BINARY) logs -f test-device

test-stop:
	@$(DOCKER_BINARY) stop test-device 2>/dev/null || true
	@$(DOCKER_BINARY) rm -f test-device 2>/dev/null || true

test-clean: test-stop
	@docker volume prune -f || true
	@echo "✅ Test cleanup complete!"

# Production service log commands
logs-prod-nodejs:
	@systemctl status iotpilot
	@echo "===== LAST 50 LOG LINES ====="
	@journalctl -u iotpilot -n 50 --no-pager

logs-prod-traefik:
	@systemctl status traefik
	@echo "===== LAST 50 LOG LINES ====="
	@journalctl -u traefik -n 50 --no-pager

logs-prod-tailscale:
	@systemctl status tailscaled
	@echo "===== LAST 50 LOG LINES ====="
	@journalctl -u tailscaled -n 50 --no-pager

logs-prod-all:
	@echo "===== NODE.JS LOGS ====="
	@journalctl -u iotpilot -n 50 --no-pager
	@echo "===== TRAEFIK LOGS ====="
	@journalctl -u traefik -n 50 --no-pager
	@echo "===== TAILSCALE LOGS ====="
	@journalctl -u tailscaled -n 50 --no-pager

# Production service management commands
restart-prod-nodejs:
	@systemctl restart iotpilot
	@echo "Node.js service restarted"

restart-prod-traefik:
	@systemctl restart traefik
	@echo "Traefik service restarted"

restart-prod-tailscale:
	@systemctl restart tailscaled
	@echo "Tailscale service restarted"

restart-prod-all:
	@systemctl restart traefik
	@systemctl restart iotpilot
	@systemctl restart tailscaled
	@echo "All services restarted"

stop-prod-all:
	@systemctl stop traefik
	@systemctl stop iotpilot
	@systemctl stop tailscaled
	@echo "All services stopped"

status-prod:
	@echo "===== SERVICE STATUS ====="
	@systemctl status traefik --no-pager
	@systemctl status iotpilot --no-pager
	@systemctl status tailscaled --no-pager

update-prod:
	@cd /opt/iotpilot && \
	 git pull --ff-only origin main && \
	 if git diff --name-only HEAD@{1} HEAD | grep -q '^app/package.json$$'; then \
	   echo "package.json changed, running npm install..."; \
	   cd app && npm install --omit=dev --no-audit --no-fund; \
	 fi && \
	 systemctl restart iotpilot
	@echo "Update complete"

# Auth toggles. Operate on /opt/iotpilot/.env; require sudo because they
# restart the iotpilot systemd unit at the end. Idempotent.
enable-auth:
	@ENV_FILE=/opt/iotpilot/.env; \
	 if grep -q '^AUTH_ENABLED=' $$ENV_FILE; then \
	   sed -i 's/^AUTH_ENABLED=.*/AUTH_ENABLED=true/' $$ENV_FILE; \
	 else \
	   echo 'AUTH_ENABLED=true' >> $$ENV_FILE; \
	 fi; \
	 if ! grep -qE '^SESSION_SECRET=.+' $$ENV_FILE; then \
	   SECRET=$$(openssl rand -base64 48 | tr -d '\n'); \
	   sed -i '/^SESSION_SECRET=/d' $$ENV_FILE; \
	   echo "SESSION_SECRET=$$SECRET" >> $$ENV_FILE; \
	   echo "Generated new SESSION_SECRET"; \
	 else \
	   echo "SESSION_SECRET already set, leaving unchanged"; \
	 fi
	@systemctl restart iotpilot
	@echo "Auth ENABLED; iotpilot restarted"

disable-auth:
	@ENV_FILE=/opt/iotpilot/.env; \
	 if grep -q '^AUTH_ENABLED=' $$ENV_FILE; then \
	   sed -i 's/^AUTH_ENABLED=.*/AUTH_ENABLED=false/' $$ENV_FILE; \
	 else \
	   echo 'AUTH_ENABLED=false' >> $$ENV_FILE; \
	 fi
	@systemctl restart iotpilot
	@echo "Auth DISABLED; iotpilot restarted"

show-auth-status:
	@ENV_FILE=/opt/iotpilot/.env; \
	 AUTH=$$(grep '^AUTH_ENABLED=' $$ENV_FILE | cut -d= -f2- || echo '(unset → false)'); \
	 if grep -qE '^SESSION_SECRET=.+' $$ENV_FILE; then SS='set'; else SS='not set'; fi; \
	 echo "AUTH_ENABLED=$$AUTH"; \
	 echo "SESSION_SECRET=$$SS"

# Setup commands
setup: sudo-setup non-sudo-setup

sudo-setup:
	@bash docker/traefik/install-cert.sh
	@HOST_NAME=$$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'"); \
	if [ -z "$$HOST_NAME" ]; then HOST_NAME="iotpilot.test"; fi; \
	if ! grep -q "$$HOST_NAME" /etc/hosts; then \
		echo "127.0.0.1 $$HOST_NAME" >> /etc/hosts; \
		echo "Added $$HOST_NAME to /etc/hosts"; \
	fi

non-sudo-setup:
	@bash docker/traefik/generate-certs.sh
	@bash docker/scripts/update-tailscale-domain.sh

# Tailscale commands
tailscale-status:
	@$(DOCKER_BINARY) exec tailscale tailscale status

tailscale-up:
	@$(DOCKER_BINARY) exec tailscale tailscale up

tailscale-down:
	@$(DOCKER_BINARY) exec tailscale tailscale down