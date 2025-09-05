.PHONY: help install-deps build test clean dev docs docker

.DEFAULT_GOAL := help

help: ## Show this help message
    @echo "OVS L2 Switch Manager - Build System"
    @echo ""
    @echo "Available targets:"
    @awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $1, $2}' $(MAKEFILE_LIST)

install-deps: ## Install all dependencies
    @npm install
    @npm run bootstrap

setup-dev: ## Setup development environment
    @bash scripts/setup/dev-environment.sh

build: ## Build all packages
    @npm run build

test: ## Run all tests
    @npm run test

dev: ## Start development environment
    @npm run dev

docs: ## Build documentation
    @npm run docs:build

clean: ## Clean build artifacts
    @npm run clean
