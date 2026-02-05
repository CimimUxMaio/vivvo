# Makefile for Vivvo Phoenix Project
#
# Usage: make [target]
#
.DEFAULT_GOAL := dev.start

# Development commands
.PHONY: dev.start
## Run the development server
dev.start:
	iex -S mix phx.server

.PHONY: dev.test
## Run the test suite using mix test
dev.test:
	mix test

.PHONY: dev.precommit
## Run code formatting, static analysis (credo), and tests before committing
dev.precommit:
	mix precommit

# Database commands
DB_CONTAINER_NAME := vivvo-db
DB_IMAGE := postgres:16-alpine
DB_PORT := 5432

.PHONY: db.up
## Ensure a Docker container for the database is running using a postgres image
db.up:
	@if [ "$$(docker ps -q -f name=$(DB_CONTAINER_NAME))" ]; then \
		echo "Database container '$(DB_CONTAINER_NAME)' is already running"; \
	elif [ "$$(docker ps -aq -f status=exited -f name=$(DB_CONTAINER_NAME))" ]; then \
		echo "Starting existing database container '$(DB_CONTAINER_NAME)'..."; \
		docker start $(DB_CONTAINER_NAME); \
	else \
		echo "Creating and starting database container '$(DB_CONTAINER_NAME)'..."; \
		docker run --name $(DB_CONTAINER_NAME) -d \
			-p $(DB_PORT):5432 \
			-e POSTGRES_USER=postgres \
			-e POSTGRES_PASSWORD=postgres \
			$(DB_IMAGE); \
	fi

.PHONY: db.setup
## Set up the database by creating it, running migrations, and seeding initial data
db.setup:
	mix ecto.setup

.PHONY: db.down
## Stop and remove the Docker container for the database
db.down:
	@if [ "$$(docker ps -aq -f name=$(DB_CONTAINER_NAME))" ]; then \
		echo "Stopping and removing database container '$(DB_CONTAINER_NAME)'..."; \
		docker stop $(DB_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		docker rm $(DB_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		echo "Database container removed"; \
	else \
		echo "No database container '$(DB_CONTAINER_NAME)' found"; \
	fi

.PHONY: db.shell
## Open a psql shell in the database container
db.shell:
	@if [ "$$(docker ps -q -f name=$(DB_CONTAINER_NAME))" ]; then \
		docker exec -it $(DB_CONTAINER_NAME) psql -U postgres -d vivvo_dev; \
	else \
		echo "Error: Database container '$(DB_CONTAINER_NAME)' is not running"; \
		echo "Run 'make db.up' to start the database container"; \
		exit 1; \
	fi

# Colors for terminal output
BOLD := \033[1m
DIM := \033[2m
RESET := \033[0m
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m

# Help command
.PHONY: help
## Display a help message listing all available commands and their descriptions
help:
	@echo ""
	@echo "$(BOLD)╔══════════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(BOLD)║                     Vivvo Phoenix Project                        ║$(RESET)"
	@echo "$(BOLD)╚══════════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(CYAN)$(BOLD)Development Commands:$(RESET)"
	@echo "  $(GREEN)dev.start$(RESET)     Run the development server (default)"
	@echo "  $(GREEN)dev.test$(RESET)      Run the test suite"
	@echo "  $(GREEN)dev.precommit$(RESET) Run code formatting, static analysis (credo), and tests"
	@echo ""
	@echo "$(CYAN)$(BOLD)Database Commands:$(RESET)"
	@echo "  $(YELLOW)db.up$(RESET)         Start the PostgreSQL Docker container"
	@echo "  $(YELLOW)db.setup$(RESET)      Create database, run migrations, and seed data"
	@echo "  $(YELLOW)db.down$(RESET)       Stop and remove the database container"
	@echo "  $(YELLOW)db.shell$(RESET)      Open a psql shell in the database container"
	@echo ""
	@echo "$(CYAN)$(BOLD)Other Commands:$(RESET)"
	@echo "  $(DIM)help$(RESET)          Display this help message"
	@echo ""
	@echo "$(BOLD)Usage:$(RESET) make [target]"
	@echo ""
