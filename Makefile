# Detect tofu (OpenTofu) first, fall back to terraform.
TOFU := $(shell command -v tofu 2>/dev/null)
TERRAFORM := $(shell command -v terraform 2>/dev/null)
TF := $(if $(TOFU),tofu,$(if $(TERRAFORM),terraform,$(error neither tofu nor terraform found)))

.PHONY: help init fmt validate isos plan apply destroy clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

init: ## Initialize the working directory (providers + lockfile)
	$(TF) init

fmt: ## Format all configuration files
	$(TF) fmt -recursive

validate: ## Validate configuration and variables
	$(TF) validate

isos: ## Phase 1: build one automated-install ISO per node (no live cluster needed)
	$(TF) apply -target=terraform_data.node_iso -auto-approve

plan: ## Plan the full configuration (phase 2 needs a reachable cluster)
	$(TF) plan

apply: ## Apply the full configuration (phase 2 needs a reachable cluster)
	$(TF) apply

destroy: ## Destroy managed state (does not touch already-installed nodes)
	$(TF) destroy

clean: ## Remove generated ISOs, answer files and hooks
	rm -rf build
