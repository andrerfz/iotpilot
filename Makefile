DOCKER_BINARY := docker-compose -f docker/docker-compose.yml --env-file .env

.PHONY: start stop restart build recreate dev deploy shell logs setup tailscale-status tailscale-up tailscale-down generate-certs force-generate-certs setup-hosts install-cert traefik-dashboard

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

# Development with live-reloading
dev: stop
	@make tailscale-down
	@make setup
	@$(DOCKER_BINARY) up
	@make tailscale-up

deploy:
	@make build
	@make setup
	@make start
	@make tailscale-up

shell:
	@$(DOCKER_BINARY) exec iotpilot bash

logs:
	@$(DOCKER_BINARY) logs -f iotpilot

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
	if [ -z "$$HOST_NAME" ]; then HOST_NAME="iotpilot.local"; fi; \
	echo "Setting up local DNS for $$HOST_NAME"; \
	if grep -q "$$HOST_NAME" /etc/hosts; then \
		echo "Hostname $$HOST_NAME already exists in /etc/hosts"; \
	else \
		sudo sh -c "echo '127.0.0.1 $$HOST_NAME' >> /etc/hosts"; \
		echo "Added $$HOST_NAME to your hosts file"; \
	fi

setup: generate-certs install-cert setup-hosts
	@echo "Setup complete! Your system is now configured for IoT Pilot."

traefik-dashboard:
	@HOST_NAME=$$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'"); \
	if [ -z "$$HOST_NAME" ]; then HOST_NAME="iotpilot.local"; fi; \
	echo "Traefik dashboard available at: http://$$HOST_NAME:8080"