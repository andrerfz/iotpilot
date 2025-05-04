DOCKER_BINARY := docker-compose -f docker/docker-compose.yml

.PHONY: start stop restart build recreate dev deploy shell logs

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
	@$(DOCKER_BINARY) up

deploy:
	@make build
	@make start

shell:
	@$(DOCKER_BINARY) exec iotpilot bash

logs:
	@$(DOCKER_BINARY) logs -f iotpilot