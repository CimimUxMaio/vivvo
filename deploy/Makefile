# Makefile for Deploy Commands
#
# Usage: make [target]
#
# This makefile contains targets for managing the deployed Vivvo container.

.DEFAULT_GOAL := help

# Validate that APP_NAME is set
ifeq ($(APP_NAME),)
  $(error APP_NAME is not set. Please set the APP_NAME environment variable before running make commands)
endif

DEPLOY_CONTAINER_NAME := $(APP_NAME)
DB_CONTAINER_NAME := vivvo-postgres
COMPOSE_FILE := docker-compose.yml
POSTGRES_USER ?= $(shell echo $$POSTGRES_USER)
POSTGRES_DB ?= $(shell echo $$POSTGRES_DB)

.PHONY: deploy.testing
## Deploy the testing environment
deploy.testing:
	@echo "🐳 Pulling latest Docker images..."
	APP_ROOT_DIR=$(HOME)/apps/$(APP_NAME) docker compose -f $(COMPOSE_FILE) pull

	@echo "⬇️  Stopping all services..."
	APP_ROOT_DIR=$(HOME)/apps/$(APP_NAME) docker compose -f $(COMPOSE_FILE) down

	@echo "🧹 Cleaning volume directories..."
	docker run --rm -v $(HOME)/apps/$(APP_NAME)/volumes:/data alpine sh -c "rm -rf /data/*"

	@echo "🚀 Starting all services..."
	APP_ROOT_DIR=$(HOME)/apps/$(APP_NAME) docker compose -f $(COMPOSE_FILE) up -d --wait --wait-timeout 60

	@echo "⚠️  Running database migrations..."
	$(MAKE) db.migrate

	@echo "⚠️  Running database seeds..."
	$(MAKE) db.seed

	@echo "🧹 Cleaning dangling Docker images..."
	docker image prune -f --filter "until=72h"

	@echo "✅ Deployment successful"

.PHONY: deploy.production
## Deploy the production environment (preserves data, runs migrations only)
deploy.production:
	@echo "🐳 Pulling latest Docker images..."
	APP_ROOT_DIR=$(HOME)/apps/$(APP_NAME) docker compose -f $(COMPOSE_FILE) pull

	@echo "⬇️  Stopping all services..."
	APP_ROOT_DIR=$(HOME)/apps/$(APP_NAME) docker compose -f $(COMPOSE_FILE) down

	@echo "🚀 Starting all services..."
	APP_ROOT_DIR=$(HOME)/apps/$(APP_NAME) docker compose -f $(COMPOSE_FILE) up -d --wait --wait-timeout 60

	@echo "⚠️  Running database migrations..."
	$(MAKE) db.migrate

	@echo "🧹 Cleaning dangling Docker images..."
	docker image prune -f --filter "until=72h"

	@echo "✅ Production deployment successful"

.PHONY: db.migrate
## Run database migrations on the deployed container
db.migrate:
	docker exec $(DEPLOY_CONTAINER_NAME) bin/vivvo eval 'Vivvo.Release.migrate()'

.PHONY: db.rollback
## Rollback the last database migration on the deployed container
db.rollback:
	docker exec $(DEPLOY_CONTAINER_NAME) bin/vivvo eval 'Vivvo.Release.rollback(Vivvo.Repo, 1)'

.PHONY: db.seed
## Run database seeds on the deployed container
db.seed:
	docker exec $(DEPLOY_CONTAINER_NAME) bin/vivvo rpc 'Vivvo.Release.seed()'

.PHONY: shell.db
## Open interactive psql shell to the postgres container
shell.db:
	docker exec -it $(DB_CONTAINER_NAME) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: shell.app
## Open interactive IEx shell to the running app container
shell.app:
	docker exec -it $(DEPLOY_CONTAINER_NAME) bin/vivvo remote

.PHONY: help
## Display a help message listing all available commands and their descriptions
help:
	@echo ""
	@echo "Deploy Commands:"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy.testing    Deploy the testing environment (resets data)"
	@echo "  deploy.production Deploy the production environment (preserves data)"
	@echo ""
	@echo "Database:"
	@echo "  db.migrate        Run database migrations on the deployed container"
	@echo "  db.rollback       Rollback the last database migration"
	@echo "  db.seed           Run database seeds on the deployed container"
	@echo ""
	@echo "Shell:"
	@echo "  shell.db          Open interactive psql shell"
	@echo "  shell.app         Open interactive IEx REPL"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
