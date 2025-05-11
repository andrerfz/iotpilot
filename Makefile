DOCKER_BINARY := docker-compose -f docker/docker-compose.yml --env-file .env

.PHONY: sudo-docker start stop restart build recreate dev deploy deploy-skip-certs
	shell logs-nodejs logs-tailscale logs-traefik setup sudo-setup non-sudo-setup
	tailscale-status tailscale-up tailscale-down generate-certs force-generate-certs
	install-cert setup-hosts update-tailscale-domain traefik-dashboard
	logs-prod-nodejs logs-prod-traefik logs-prod-tailscale logs-prod-avahi logs-prod-all
	restart-prod-nodejs restart-prod-traefik restart-prod-tailscale restart-prod-all stop-prod-all status-prod

sudo-docker:
	@sudo chown -R $(shell whoami) ~/.docker
	@echo "Docker permissions fixed."

start:
	@$(DOCKER_BINARY) up -d --remove-orphans

stop:
	@$(DOCKER_BINARY) down --remove-orphans

build:
	@$(DOCKER_BINARY) build --no-cache

recreate:
	@make stop
	@$(DOCKER_BINARY) up -d --remove-orphans --no-deps --build

restart: stop start

sudo-setup: install-cert setup-hosts
	@echo "Sudo operations completed successfully."

non-sudo-setup: generate-certs update-tailscale-domain
	@echo "Non-sudo operations completed successfully."

setup:
	@echo "Running setup operations that require sudo..."
	@make sudo-setup
	@echo "Running setup operations that don't require sudo..."
	@make non-sudo-setup
	@echo "Setup complete! Your system is now configured for IoT Pilot."

dev: stop
	@make tailscale-down
	@make setup
	@$(DOCKER_BINARY) up
	@make tailscale-up

deploy-app: build start tailscale-up
	@echo "Application deployed successfully."

deploy:
	@make stop
	@echo "Running setup operations that require sudo..."
	@make sudo-setup
	@echo "Running setup operations that don't require sudo..."
	@make non-sudo-setup
	@echo "Deploying application..."
	@make deploy-app

deploy-skip-certs:
	@make build
	@make start
	@make tailscale-up

shell:
	@$(DOCKER_BINARY) exec iotpilot bash

logs-nodejs:
	@$(DOCKER_BINARY) logs -f iotpilot

logs-tailscale:
	@$(DOCKER_BINARY) logs -f tailscale

logs-traefik:
	@$(DOCKER_BINARY) logs -f traefik

# Tailscale specific commands
tailscale-status:
	@$(DOCKER_BINARY) exec tailscale tailscale status

tailscale-up:
	@$(DOCKER_BINARY) exec tailscale tailscale up

tailscale-down:
	@$(DOCKER_BINARY) exec tailscale tailscale down

# Certificate and DNS commands
generate-certs:
	@bash docker/traefik/generate-certs.sh

force-generate-certs:
	@bash docker/traefik/generate-certs.sh --force

install-cert:
	@bash docker/traefik/install-cert.sh

setup-hosts:
	@HOST_NAME=$$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'"); \
	if [ -z "$$HOST_NAME" ]; then HOST_NAME="iotpilot.test"; fi; \
	echo "Setting up local DNS for $$HOST_NAME"; \
	if grep -q "$$HOST_NAME" /etc/hosts; then \
		echo "Hostname $$HOST_NAME already exists in /etc/hosts"; \
	else \
		echo "127.0.0.1 $$HOST_NAME" >> /etc/hosts; \
		echo "Added $$HOST_NAME to your hosts file"; \
	fi

update-tailscale-domain:
	@bash docker/scripts/update-tailscale-domain.sh

traefik-dashboard:
	@HOST_NAME=$$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'"); \
	if [ -z "$$HOST_NAME" ]; then HOST_NAME="iotpilot.test"; fi; \
	echo "Traefik dashboard available at: http://$$HOST_NAME:8080"


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

logs-prod-avahi:
	@systemctl status avahi-daemon
	@echo "===== LAST 50 LOG LINES ====="
	@journalctl -u avahi-daemon -n 50 --no-pager

logs-prod-all:
	@echo "===== NODE.JS LOGS ====="
	@journalctl -u iotpilot -n 50 --no-pager
	@echo "===== TRAEFIK LOGS ====="
	@journalctl -u traefik -n 50 --no-pager
	@echo "===== TAILSCALE LOGS ====="
	@journalctl -u tailscaled -n 50 --no-pager
	@echo "===== AVAHI LOGS ====="
	@journalctl -u avahi-daemon -n 50 --no-pager

# Production service management commands
restart-prod-nodejs:
	@systemctl restart iotpilot
	@echo "Node.js service restarted"

restart-prod-traefik:
	@systemctl restart traefik
	@echo "Traefik service restarted"

restart-prod-tailscale:
	@systemctl restart tailscaled
	@echo "Tailscal service restarted"

restart-prod-all:
	@systemctl restart traefik
	@systemctl restart iotpilot
	@systemctl restart tailscaled
	@echo "All services restarted"

stop-prod-all:
	@systemctl stop traefik
	@systemctl stop iotpilot
	@systemctl stop tailscaled
	@echo "All services stoped"

status-prod:
	@echo "===== SERVICE STATUS ====="
	@systemctl status traefik --no-pager
	@systemctl status iotpilot --no-pager
	@systemctl status tailscaled --no-pager
	@systemctl status avahi-daemon --no-pager