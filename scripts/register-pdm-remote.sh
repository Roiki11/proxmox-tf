#!/usr/bin/env bash
# Registers a Proxmox VE cluster as a remote in Proxmox Datacenter Manager
# through its REST API — no SSH access to the PDM host required.
#
# Endpoints used (all under PDM_API_URL/api2/json):
#   POST /access/ticket                           ticket auth (user + password)
#   GET  /remotes/remote                          list remotes (idempotency)
#   POST /remotes/remote                          create remote
#   PUT  /remotes/remote/{id}                     update remote
#   POST /remotes/remote/{id}/probe-certificate   verify node TLS connectivity
#   DELETE /remotes/remote/{id}?delete-token=..   remove remote
#
# `--remove` as the first argument removes the remote instead; in that mode
# the inputs arrive as a JSON blob in PDM_CONFIG (set by the destroy
# provisioner). All other inputs come in via the environment (see pdm.tf and
# scripts/pdm-api-lib.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/pdm-api-lib.sh
source "$SCRIPT_DIR/pdm-api-lib.sh"

MODE="add"
if [ "${1:-}" = "--remove" ]; then
    MODE="remove"
fi

pdm_auth_init

REMOTE_ID="${REMOTE_ID:?REMOTE_ID must be set}"
REMOTE_TYPE="${REMOTE_TYPE:-pve}"
AUTHID="${AUTHID:-}"
TOKEN_SECRET="${TOKEN_SECRET:-}"
NODE_ADDRESSES="${NODE_ADDRESSES:-[]}"
WEB_URL="${WEB_URL:-}"
VERIFY_NODES="${VERIFY_NODES:-0}"
DELETE_TOKEN_ON_DESTROY="${DELETE_TOKEN_ON_DESTROY:-1}"

if [ "$MODE" = "remove" ]; then
    echo "Removing remote '$REMOTE_ID' from PDM at $PDM_BASE_URL"
    if [ "$(pdm_remote_exists "$REMOTE_ID")" != "yes" ]; then
        echo "Remote '$REMOTE_ID' not present; nothing to do"
        exit 0
    fi
    pdm_api_quiet DELETE "/remotes/remote/$REMOTE_ID?delete-token=$DELETE_TOKEN_ON_DESTROY"
    echo "Remote '$REMOTE_ID' removed"
    exit 0
fi

if [ -z "$AUTHID" ] || [ -z "$TOKEN_SECRET" ]; then
    echo "ERROR: AUTHID and TOKEN_SECRET must be set to add a remote" >&2
    exit 1
fi

if [ "$(pdm_remote_exists "$REMOTE_ID")" = "yes" ]; then
    echo "Remote '$REMOTE_ID' already exists in PDM; updating it"
    pdm_api_quiet PUT "/remotes/remote/$REMOTE_ID" "$(python3 -c 'import json,sys
print(json.dumps({
    "authid": sys.argv[1],
    "token": sys.argv[2],
    "nodes": json.loads(sys.argv[3]),
    **({"web-url": sys.argv[4]} if sys.argv[4] else {}),
}))' "$AUTHID" "$TOKEN_SECRET" "$NODE_ADDRESSES" "$WEB_URL")"
else
    echo "Registering remote '$REMOTE_ID' in PDM at $PDM_BASE_URL"
    pdm_api_quiet POST /remotes/remote "$(python3 -c 'import json,sys
print(json.dumps({
    "id": sys.argv[1],
    "type": sys.argv[2],
    "authid": sys.argv[3],
    "token": sys.argv[4],
    "nodes": json.loads(sys.argv[5]),
    **({"web-url": sys.argv[6]} if sys.argv[6] else {}),
}))' "$REMOTE_ID" "$REMOTE_TYPE" "$AUTHID" "$TOKEN_SECRET" "$NODE_ADDRESSES" "$WEB_URL")"
fi

if [ "$VERIFY_NODES" = "1" ]; then
    python3 -c 'import json,sys; print("\n".join(json.loads(sys.argv[1])))' "$NODE_ADDRESSES" |
    while IFS= read -r node; do
        if pdm_api_quiet POST "/remotes/remote/$REMOTE_ID/probe-certificate" \
            "$(python3 -c 'import json,sys; print(json.dumps({"id": sys.argv[1], "node": sys.argv[2]}))' "$REMOTE_ID" "$node")"; then
            echo "Node '$node': TLS certificate probe OK"
        else
            echo "WARNING: node '$node' TLS certificate probe failed; PDM may need the issuing CA in its trust store (or pin the fingerprint via 'proxmox-datacenter-manager-client remote set-fingerprint')" >&2
        fi
    done
fi

echo "Done."
