# Makefile for Deploy Commands
#
# Usage: make [target]
#
# This makefile contains targets for managing the deployed Vivvo container.

APP_NAME := vivvo
DEPLOY_CONTAINER_NAME := $(APP_NAME)
COMPOSE_FILE := deploy/docker-compose.testing.yml

.PHONY: deploy.testing
## Deploy the testing environment
deploy.testing:
	@echo "📥 Pulling latest repository..."
	git pull origin ci-cd-pipeline

	@echo "🐳 Pulling latest Docker images..."
	docker compose -f $(COMPOSE_FILE) pull

	@echo "🚀 Starting services and waiting for healthchecks..."
	docker compose -f $(COMPOSE_FILE) up -d --wait --wait-timeout 60

	@echo "🔄 Resetting database..."
	$(MAKE) db.reset

	@echo "🧹 Cleaning unused Docker images..."
	docker image prune -af --filter "until=72h"

	@echo "✅ Deployment successful"

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
	docker exec $(DEPLOY_CONTAINER_NAME) bin/vivvo eval 'Vivvo.Release.seed()'

.PHONY: db.reset
## Reset database (drop, create, migrate, seed) on the deployed container
db.reset:
	docker exec $(DEPLOY_CONTAINER_NAME) bin/vivvo eval 'Vivvo.Release.reset()'

.PHONY: help
## Display a help message listing all available commands and their descriptions
help:
	@echo ""
	@echo "Deploy Commands:"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy.testing  Deploy the testing environment"
	@echo ""
	@echo "Database:"
	@echo "  db.migrate      Run database migrations on the deployed container"
	@echo "  db.rollback     Rollback the last database migration"
	@echo "  db.seed         Run database seeds on the deployed container"
	@echo "  db.reset        Reset database (drop, create, migrate, seed)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
