# Saaf underwriting-assist agent — infrastructure
# Convenience targets. The CI workflows call the same underlying commands.

SHELL := /bin/bash
.DEFAULT_GOAL := help

IMAGE      ?= underwriting-agent
TAG        ?= dev
ENV        ?= dev
TF_DIR      = terraform/environments/$(ENV)

# ---------------------------------------------------------------------------
# App (reference agent — vendored, not modified)
# ---------------------------------------------------------------------------
.PHONY: install
install: ## Install the agent + dev deps into the active venv
	pip install -e ".[dev]"

.PHONY: lint
lint: ## Ruff lint the agent source
	ruff check src tests

.PHONY: test
test: ## Run the pytest smoke suite
	pytest -q

.PHONY: docker-build
docker-build: ## Build the agent container image
	docker build -t $(IMAGE):$(TAG) .

.PHONY: run-local
run-local: ## Run the agent locally (mock LLM, no creds needed)
	uvicorn agent.main:app --app-dir src --host 0.0.0.0 --port 8080 --reload

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
.PHONY: tf-fmt
tf-fmt: ## terraform fmt across the tree
	terraform fmt -recursive terraform

.PHONY: tf-validate
tf-validate: ## init (no backend) + validate every environment and module
	@./scripts/tf-validate-all.sh

.PHONY: tf-plan
tf-plan: ## terraform plan for ENV=dev|staging|prod
	cd $(TF_DIR) && terraform init && terraform plan

.PHONY: tf-security
tf-security: ## Static security scan of the Terraform (tfsec)
	tfsec terraform --soft-fail

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
