# Detect tofu (OpenTofu) first, fall back to terraform.
TOFU := $(shell command -v tofu 2>/dev/null)
TERRAFORM := $(shell command -v terraform 2>/dev/null)
TF := $(if $(TOFU),tofu,$(if $(TERRAFORM),terraform,$(error neither tofu nor terraform found)))

.PHONY: help init fmt validate isos plan apply destroy clean \
	pdm-node-apply pdm-node-status pdm-node-config pdm-node-network \
	pdm-node-updates pdm-node-repositories pdm-node-subscription \
	pdm-node-storage pdm-node-apt-update pdm-updates-refresh pdm-updates-summary \
	pve-storage pve-network pve-sdn pve-ceph \
	iso-serve iso-serve-stop node-install node-status node-power \
	node-eject node-wait node-wait-all

# PDM CLI tasks read their connection settings from the environment
# (PDM_API_URL, PDM_API_USER/PDM_API_PASSWORD or PDM_API_TOKEN, and optionally
# PDM_API_INSECURE/PDM_API_CA_FILE); PDM_REMOTE_ID defaults to the cluster name.
PDM_REMOTE_ID ?= $(shell tofu output -raw pdm_remote_id 2>/dev/null)
PDM_NODE ?=
ISO_HTTP_PORT ?= 8080

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


# --- Direct cluster configuration tasks (bpg/proxmox; NODE-scoped resources) ---

pve-storage: ## Declare/apply storage definitions on the cluster (variables-storage.tf)
	$(TF) apply -target=proxmox_storage_directory.storage \
		-target=proxmox_storage_lvm.storage \
		-target=proxmox_storage_lvmthin.storage \
		-target=proxmox_storage_zfspool.storage \
		-target=proxmox_storage_nfs.storage \
		-target=proxmox_storage_cifs.storage \
		-target=proxmox_storage_pbs.storage

pve-network: ## Declare/apply node network interfaces + reload applier (variables-network.tf)
	$(TF) apply -target=proxmox_network_linux_vlan.vlans \
		-target=proxmox_network_linux_bond.bonds \
		-target=proxmox_network_linux_bridge.bridges \
		-target=proxmox_network_applier.nodes

pve-sdn: ## Declare/apply SDN zones, VNets, subnets + applier (variables-sdn.tf)
	$(TF) apply -target=proxmox_sdn_zone_simple.zones \
		-target=proxmox_sdn_zone_vlan.zones \
		-target=proxmox_sdn_zone_vxlan.zones \
		-target=proxmox_sdn_zone_evpn.zones \
		-target=proxmox_sdn_vnet.vnets \
		-target=proxmox_sdn_subnet.subnets \
		-target=proxmox_sdn_applier.apply

pve-ceph: ## Declare/apply Ceph pools (variables-ceph.tf)
	$(TF) apply -target=proxmox_ceph_pool.pools


# --- Node install tasks (Redfish/BMC; REDFISH_NODE=<name> or all) ------------
#
# Prerequisites per node: bmc = { address, username, ... } in var.nodes (the
# BMC password lives in the Vault field bmc_<node>_password), the node's ISO
# built with `make isos`, and the ISO served over HTTP with `make iso-serve`
# (iso_http_base_url must be reachable from the BMC).

REDFISH_NODE ?= $(PDM_NODE)

iso-serve: ## Serve build/iso over HTTP for Redfish virtual media (port from ISO_HTTP_PORT)
	@test -d build/iso || { echo "no build/iso — run 'make isos' first"; exit 1; }
	@test -z "$$($(SHELL) -c 'lsof -iTCP:$(ISO_HTTP_PORT) -sTCP:LISTEN 2>/dev/null' | head -n1)" || { echo "port $(ISO_HTTP_PORT) already in use"; exit 1; }
	nohup python3 -m http.server $(ISO_HTTP_PORT) --directory build/iso > build/iso-serve.log 2>&1 & echo $$! > build/iso-serve.pid
	@echo "Serving build/iso at http://*:${ISO_HTTP_PORT} (pid $$(cat build/iso-serve.pid))"

iso-serve-stop: ## Stop the ISO HTTP server started by iso-serve
	@test -f build/iso-serve.pid && kill "$$(cat build/iso-serve.pid)" && rm -f build/iso-serve.pid || echo "not running"

node-install: ## Install machines via the Redfish provider: attach ISO, one-time boot, power on (REDFISH_NODE=<name> targets one node; forces node_install_enabled for the run)
	$(if $(REDFISH_NODE),\
		$(TF) apply -var 'node_install_enabled=true' -target='redfish_virtual_media.install["$(REDFISH_NODE)"]' -target='redfish_boot_source_override.install["$(REDFISH_NODE)"]' -target='redfish_power.install["$(REDFISH_NODE)"]',\
		$(TF) apply -var 'node_install_enabled=true' -target=redfish_virtual_media.install -target=redfish_boot_source_override.install -target=redfish_power.install)

node-status: ## Show the BMC power state of a node (REDFISH_NODE=<name>)
	@test -n "$(REDFISH_NODE)" || { echo "usage: make node-status REDFISH_NODE=node01"; exit 1; }
	@./scripts/node-redfish.sh status "$(REDFISH_NODE)"

node-power: ## Power control via Redfish (REDFISH_NODE=<name> REDFISH_POWER_ACTION=<On|ForceOff|GracefulShutdown|ForceRestart|GracefulRestart>)
	@test -n "$(REDFISH_NODE)" -a -n "$(REDFISH_POWER_ACTION)" || { echo "usage: make node-power REDFISH_NODE=node01 REDFISH_POWER_ACTION=GracefulRestart"; exit 1; }
	@./scripts/node-redfish.sh power "$(REDFISH_NODE)" "$(REDFISH_POWER_ACTION)"

node-eject: ## Eject the node's virtual media via Redfish (REDFISH_NODE=<name>)
	@test -n "$(REDFISH_NODE)" || { echo "usage: make node-eject REDFISH_NODE=node01"; exit 1; }
	@./scripts/node-redfish.sh eject "$(REDFISH_NODE)"

node-wait: ## Wait until a node's PVE API responds after installation (REDFISH_NODE=<name>; REDFISH_WAIT_TIMEOUT seconds)
	@test -n "$(REDFISH_NODE)" || { echo "usage: make node-wait REDFISH_NODE=node01"; exit 1; }
	@./scripts/node-redfish.sh wait "$(REDFISH_NODE)"

node-wait-all: ## Wait for every node's PVE API to respond
	@for node in $$(tofu output -json node_bmcs 2>/dev/null | python3 -c 'import json,sys; print(" ".join(k for k, v in json.load(sys.stdin).items() if v))' 2>/dev/null); do \
		./scripts/node-redfish.sh wait "$$node" || exit 1; \
	done
