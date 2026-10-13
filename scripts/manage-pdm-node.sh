#!/usr/bin/env bash
# Manages Proxmox VE node configuration through the Proxmox Datacenter
# Manager REST API (proxied endpoints under /pve/remotes/{remote}/nodes/...).
#
# Usage:
#   manage-pdm-node.sh --apply-node <node>    apply pdm_node_config for a node
#                                             (apt update + firewall options)
#   manage-pdm-node.sh status <node>          node status
#   manage-pdm-node.sh config <node>          node configuration
#   manage-pdm-node.sh network <node>         network interfaces (read-only)
#   manage-pdm-node.sh updates <node>         pending APT updates
#   manage-pdm-node.sh repositories <node>    APT repositories
#   manage-pdm-node.sh subscription <node>    subscription status
#   manage-pdm-node.sh storage <node>         storage status
#   manage-pdm-node.sh apt-update <node>      trigger APT database update
#   manage-pdm-node.sh refresh-updates        refresh PDM's cached update info
#                                             for the whole remote
#
# Inputs via environment (see scripts/pdm-api-lib.sh):
#   PDM_API_URL, PDM_API_USER, PDM_API_PASSWORD, PDM_API_TOKEN,
#   PDM_API_INSECURE, PDM_API_CA_FILE, PDM_REMOTE_ID (remote id in PDM)
#
# --apply-node is also driven by a JSON blob in PDM_NODE_CONFIG with fields:
#   apt_update         boolean  trigger POST .../apt/update
#   firewall_options   object   PUT .../firewall/options body
#
# Read-only endpoints are proxied by PDM; network/subscription writes and
# power commands are NOT available through PDM (use PVE directly).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/pdm-api-lib.sh
source "$SCRIPT_DIR/pdm-api-lib.sh"

CMD="${1:-}"
NODE="${2:-}"

PDM_REMOTE_ID="${PDM_REMOTE_ID:?PDM_REMOTE_ID must be set (remote id in PDM)}"

node_path() { # node_path <node> <suffix>
    printf '/pve/remotes/%s/nodes/%s%s' "$PDM_REMOTE_ID" "$1" "${2:-}"
}

apply_node() {
    NODE="$1"
    [ -n "${PDM_NODE_CONFIG:-}" ] || { echo "ERROR: PDM_NODE_CONFIG is empty" >&2; exit 1; }

    APT_UPDATE=$(printf '%s' "$PDM_NODE_CONFIG" | pdm_json_get "bool(d.get('apt_update', False))")

    if [ "$APT_UPDATE" = "True" ]; then
        echo "[$NODE] refreshing APT package database via PDM"
        pdm_api_quiet POST "$(node_path "$NODE" /apt/update)"
    fi

    if printf '%s' "$PDM_NODE_CONFIG" | python3 -c 'import json,sys
d = json.load(sys.stdin)
opts = d.get("firewall_options") or {}
sys.exit(0 if opts else 1)'; then
        echo "[$NODE] applying node firewall options via PDM"
        FIREWALL_BODY=$(printf '%s' "$PDM_NODE_CONFIG" | pdm_json_get "json.dumps(d['firewall_options'])")
        pdm_api_quiet PUT "$(node_path "$NODE" /firewall/options)" "$FIREWALL_BODY"
    fi

    echo "[$NODE] node configuration applied"
}

case "$CMD" in
    --apply-node)
        [ -n "$NODE" ] || { echo "ERROR: --apply-node requires a node name" >&2; exit 1; }
        pdm_auth_init
        apply_node "$NODE"
        ;;
    status|config|network|updates|repositories|subscription|storage)
        [ -n "$NODE" ] || { echo "ERROR: '$CMD' requires a node name" >&2; exit 1; }
        pdm_auth_init
        case "$CMD" in
            status)        PATH_SUFFIX= ;;
            config)        PATH_SUFFIX=/config ;;
            network)       PATH_SUFFIX=/network ;;
            updates)       PATH_SUFFIX=/apt/update ;;
            repositories)  PATH_SUFFIX=/apt/repositories ;;
            subscription)  PATH_SUFFIX=/subscription ;;
            storage)       PATH_SUFFIX=/storage ;;
        esac
        pdm_api GET "$(node_path "$NODE" "$PATH_SUFFIX")" | python3 -m json.tool
        ;;
    apt-update)
        [ -n "$NODE" ] || { echo "ERROR: 'apt-update' requires a node name" >&2; exit 1; }
        pdm_auth_init
        echo "[$NODE] refreshing APT package database via PDM"
        pdm_api_quiet POST "$(node_path "$NODE" /apt/update)"
        echo "[$NODE] APT database update triggered"
        ;;
    refresh-updates)
        pdm_auth_init
        echo "Refreshing PDM's cached update information for all remotes"
        pdm_api_quiet POST /remotes/updates/refresh
        echo "Update information refreshed"
        ;;
    updates-summary)
        pdm_auth_init
        pdm_api GET /remotes/updates/summary | python3 -m json.tool
        ;;
    *)
        echo "ERROR: unknown command '$CMD'" >&2
        sed -n '/^# Usage:/,/^set -euo/p' "$0" >&2
        exit 1
        ;;
esac
