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
# provisioner). All other inputs come in via the environment (see pdm.tf).
set -euo pipefail

MODE="add"
if [ "${1:-}" = "--remove" ]; then
    MODE="remove"
fi

# In remove mode (called from a destroy provisioner) all inputs arrive as a
# JSON blob in PDM_CONFIG; unpack them into the regular variables.
if [ -n "${PDM_CONFIG:-}" ]; then
    eval "$(python3 -c 'import json,sys,shlex
cfg = json.loads(sys.argv[1])
mapping = {
    "api_url": "PDM_API_URL",
    "api_user": "PDM_API_USER",
    "api_password": "PDM_API_PASSWORD",
    "api_token": "PDM_API_TOKEN",
    "insecure": "PDM_API_INSECURE",
    "ca_file": "PDM_API_CA_FILE",
    "remote_id": "REMOTE_ID",
    "delete_token": "DELETE_TOKEN_ON_DESTROY",
}
for key, var in mapping.items():
    print("%s=%s" % (var, shlex.quote(str(cfg.get(key, "")))))' "$PDM_CONFIG")"
fi

BASE_URL="${PDM_API_URL%/}"
BASE_URL="${BASE_URL:?PDM_API_URL must be set}"
REMOTE_ID="${REMOTE_ID:?REMOTE_ID must be set}"
REMOTE_TYPE="${REMOTE_TYPE:-pve}"
AUTHID="${AUTHID:-}"
TOKEN_SECRET="${TOKEN_SECRET:-}"
NODE_ADDRESSES="${NODE_ADDRESSES:-[]}"
WEB_URL="${WEB_URL:-}"
VERIFY_NODES="${VERIFY_NODES:-0}"
DELETE_TOKEN_ON_DESTROY="${DELETE_TOKEN_ON_DESTROY:-1}"
PDM_API_USER="${PDM_API_USER:-root@pam}"
PDM_API_PASSWORD="${PDM_API_PASSWORD:-}"
PDM_API_TOKEN="${PDM_API_TOKEN:-}"
PDM_API_INSECURE="${PDM_API_INSECURE:-1}"
PDM_API_CA_FILE="${PDM_API_CA_FILE:-}"

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

CURL_TLS=()
if [ -n "$PDM_API_CA_FILE" ]; then
    CURL_TLS=(--cacert "$PDM_API_CA_FILE")
elif [ "$PDM_API_INSECURE" = "1" ]; then
    CURL_TLS=(-k)
fi

json_get() { # json_get <python expression over 'd'>
    python3 -c "import json,sys
d = json.load(sys.stdin)
print(eval(sys.argv[1]))" "$1"
}

# --- authentication ----------------------------------------------------------
AUTH=()
if [ -n "$PDM_API_TOKEN" ]; then
    AUTH=(-H "Authorization: PVEAPITicket=$PDM_API_TOKEN")
else
    RESP=$(curl -sS "${CURL_TLS[@]}" --max-time 30 \
        -c "$COOKIE_JAR" \
        -H 'Content-Type: application/json' \
        -d "$(python3 -c 'import json,sys; print(json.dumps({"username": sys.argv[1], "password": sys.argv[2]}))' "$PDM_API_USER" "$PDM_API_PASSWORD")" \
        "$BASE_URL/api2/json/access/ticket")

    TICKET=$(printf '%s' "$RESP" | json_get "d['data']['ticket']")
    CSRF=$(printf '%s' "$RESP" | json_get "d['data']['CSRFPreventionToken']")
    AUTH=(-b "$COOKIE_JAR" -H "CSRFPreventionToken: $CSRF")
fi

api() { # api <method> <path> [json-body]
    local method="$1" path="$2" body="${3:-}" code out
    local args=(curl -sS "${CURL_TLS[@]}" --max-time 60 -X "$method" "${AUTH[@]}" -w $'\n%{http_code}' -H 'Content-Type: application/json')
    [ -n "$body" ] && args+=(-d "$body")
    out=$("${args[@]}" "$BASE_URL/api2/json$path")
    code=$(printf '%s' "$out" | tail -n1)
    [ "$code" = "200" ] || { echo "ERROR: $method $path returned HTTP $code: ${out%$'\n'*}" >&2; exit 1; }
    printf '%s' "${out%$'\n'*}"
}

remote_exists() {
    api GET /remotes/remote | python3 -c 'import json,sys
ids = [r["id"] for r in json.load(sys.stdin)["data"]]
print("yes" if sys.argv[1] in ids else "no")' "$REMOTE_ID"
}

if [ "$MODE" = "remove" ]; then
    echo "Removing remote '$REMOTE_ID' from PDM at $BASE_URL"
    if [ "$(remote_exists)" != "yes" ]; then
        echo "Remote '$REMOTE_ID' not present; nothing to do"
        exit 0
    fi
    api DELETE "/remotes/remote/$REMOTE_ID?delete-token=$DELETE_TOKEN_ON_DESTROY" >/dev/null >/dev/null
    echo "Remote '$REMOTE_ID' removed"
    exit 0
fi

if [ -z "$AUTHID" ] || [ -z "$TOKEN_SECRET" ]; then
    echo "ERROR: AUTHID and TOKEN_SECRET must be set to add a remote" >&2
    exit 1
fi

if [ "$(remote_exists)" = "yes" ]; then
    echo "Remote '$REMOTE_ID' already exists in PDM; updating it"
    api PUT "/remotes/remote/$REMOTE_ID" "$(python3 -c 'import json,sys
print(json.dumps({
    "authid": sys.argv[1],
    "token": sys.argv[2],
    "nodes": json.loads(sys.argv[3]),
    **({"web-url": sys.argv[4]} if sys.argv[4] else {}),
}))' "$AUTHID" "$TOKEN_SECRET" "$NODE_ADDRESSES" "$WEB_URL")" >/dev/null
else
    echo "Registering remote '$REMOTE_ID' in PDM at $BASE_URL"
    api POST /remotes/remote "$(python3 -c 'import json,sys
print(json.dumps({
    "id": sys.argv[1],
    "type": sys.argv[2],
    "authid": sys.argv[3],
    "token": sys.argv[4],
    "nodes": json.loads(sys.argv[5]),
    **({"web-url": sys.argv[6]} if sys.argv[6] else {}),
}))' "$REMOTE_ID" "$REMOTE_TYPE" "$AUTHID" "$TOKEN_SECRET" "$NODE_ADDRESSES" "$WEB_URL")" >/dev/null
fi

if [ "$VERIFY_NODES" = "1" ]; then
    python3 -c 'import json,sys; print("\n".join(json.loads(sys.argv[1])))' "$NODE_ADDRESSES" |
    while IFS= read -r node; do
        if api POST "/remotes/remote/$REMOTE_ID/probe-certificate" \
            "$(python3 -c 'import json,sys; print(json.dumps({"id": sys.argv[1], "node": sys.argv[2]}))' "$REMOTE_ID" "$node")" >/dev/null; then
            echo "Node '$node': TLS certificate probe OK"
        else
            echo "WARNING: node '$node' TLS certificate probe failed; PDM may need the issuing CA in its trust store (or pin the fingerprint via 'proxmox-datacenter-manager-client remote set-fingerprint')" >&2
        fi
    done
fi

echo "Done."
