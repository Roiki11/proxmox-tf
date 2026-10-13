# Detect tofu (OpenTofu) first, fall back to terraform.
TOFU := $(shell command -v tofu 2>/dev/null)
TERRAFORM := $(shell command -v terraform 2>/dev/null)
TF := $(if $(TOFU),tofu,$(if $(TERRAFORM),terraform,$(error neither tofu nor terraform found)))

.PHONY: help init fmt validate isos plan apply destroy clean \
	pdm-node-apply pdm-node-status pdm-node-config pdm-node-network \
	pdm-node-updates pdm-node-repositories pdm-node-subscription \
	pdm-node-storage pdm-node-apt-update pdm-updates-refresh pdm-updates-summary

# PDM CLI tasks read their connection settings from the environment
# (PDM_API_URL, PDM_API_USER/PDM_API_PASSWORD or PDM_API_TOKEN, and optionally
# PDM_API_INSECURE/PDM_API_CA_FILE); PDM_REMOTE_ID defaults to the cluster name.
PDM_REMOTE_ID ?= $(shell tofu output -raw pdm_remote_id 2>/dev/null)
PDM_NODE ?=

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

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

# --- PDM node configuration tasks (NODE=<name>; connection via PDM_* env) ---

pdm-node-apply: ## Apply var.pdm_node_config through PDM (NODE=<name> targets one node)
	$(if $(PDM_NODE),tofu apply -target='terraform_data.pdm_node_config["$(PDM_NODE)"]',tofu apply -target=terraform_data.pdm_node_config)

pdm-node-status: ## Show node status via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-status PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh status "$(PDM_NODE)"

pdm-node-config: ## Show node configuration via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-config PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh config "$(PDM_NODE)"

pdm-node-network: ## Show node network interfaces via PDM, read-only (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-network PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh network "$(PDM_NODE)"

pdm-node-updates: ## List pending APT updates via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-updates PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh updates "$(PDM_NODE)"

pdm-node-repositories: ## Show APT repositories via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-repositories PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh repositories "$(PDM_NODE)"

pdm-node-subscription: ## Show node subscription status via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-subscription PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh subscription "$(PDM_NODE)"

pdm-node-storage: ## Show node storage status via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-storage PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh storage "$(PDM_NODE)"

pdm-node-apt-update: ## Trigger an APT database update via PDM (NODE=<name>)
	@test -n "$(PDM_NODE)" || { echo "usage: make pdm-node-apt-update PDM_NODE=node01"; exit 1; }
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh apt-update "$(PDM_NODE)"

pdm-updates-refresh: ## Refresh PDM's cached update summary for all remotes
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh refresh-updates

pdm-updates-summary: ## Show PDM's cached update summary for all remotes
	@PDM_REMOTE_ID="$(PDM_REMOTE_ID)" ./scripts/manage-pdm-node.sh updates-summary
