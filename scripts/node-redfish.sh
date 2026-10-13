#!/usr/bin/env bash
# Boots (or inspects/controls) bare-metal Proxmox nodes through the Redfish
# API of their BMC (iDRAC, iLO, Supermicro, OpenBMC, ...).
#
# Usage:
#   (machine installation moved to the dell/redfish provider — see redfish.tf;
#    use `make node-install` or `make node-install REDFISH_NODE=<name>`)
#   node-redfish.sh status <node>      BMC power state of the node
#   node-redfish.sh power <node> <On|ForceOff|GracefulShutdown|ForceRestart|GracefulRestart>
#   node-redfish.sh eject <node>       remove the virtual media
#   node-redfish.sh wait <node>        block until the PVE API on the node's
#                                      management IP responds; timeout via
#                                      REDFISH_WAIT_TIMEOUT (default 3600s)
#
# Node information comes from the `node_bmcs` terraform output (created by
# the bootstrap apply); override with REDFISH_BMC_URL, REDFISH_BMC_USER,
# REDFISH_BMC_PASSWORD, REDFISH_PASSWORD_FIELD, REDFISH_BMC_BOOT_TARGET,
# REDFISH_MGMT_IP and REDFISH_ISO_URL environment variables.
#
# Authentication: Redfish session auth by default (X-Auth-Token) with basic
# auth fallback; REDFISH_AUTH_MODE=basic forces Basic. BMC passwords come
# from REDFISH_BMC_PASSWORD or the Vault KV field (VAULT_ADDR/VAULT_TOKEN,
# VAULT_KV_MOUNT/VAULT_SECRET_PATH). REDFISH_INSECURE=1 (default, self-signed
# BMC certs) or REDFISH_CA_FILE. The ISO must be reachable from the BMC over
# HTTP — run `make iso-serve` (or your own webserver).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CURL_TLS=()
if [ -n "${REDFISH_CA_FILE:-}" ]; then
    CURL_TLS=(--cacert "$REDFISH_CA_FILE")
elif [ "${REDFISH_INSECURE:-1}" = "1" ]; then
    CURL_TLS=(-k)
fi

json_get() { # json_get <python expression over 'd'>
    python3 -c "import json,sys
d = json.load(sys.stdin)
print(eval(sys.argv[1]))" "$1"
}


# --- node information --------------------------------------------------------
get_node_info() { # sets RF_BMC_URL, RF_USER, RF_PASSWORD_FIELD, RF_BOOT_TARGET, RF_MGMT_IP, RF_ISO_URL
    local node="$1"
    RF_BMC_URL="${REDFISH_BMC_URL:-}"
    RF_USER="${REDFISH_BMC_USER:-}"
    RF_PASSWORD_FIELD="${REDFISH_PASSWORD_FIELD:-}"
    RF_BOOT_TARGET="${REDFISH_BMC_BOOT_TARGET:-Cd}"
    RF_MGMT_IP="${REDFISH_MGMT_IP:-}"
    RF_ISO_URL="${REDFISH_ISO_URL:-}"

    if [ -f "$TF_DIR/terraform.tfstate" ]; then
        INFO=$(tofu -chdir="$TF_DIR" output -json node_bmcs 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1]) or {}))' "$node" 2>/dev/null || true)
        if [ -n "$INFO" ] && [ "$INFO" != "{}" ]; then
            [ -z "$RF_BMC_URL" ] && RF_BMC_URL=$(printf '%s' "$INFO" | json_get "d.get('address','')")
            [ -z "$RF_USER" ] && RF_USER=$(printf '%s' "$INFO" | json_get "d.get('username','')")
            [ -z "$RF_PASSWORD_FIELD" ] && RF_PASSWORD_FIELD=$(printf '%s' "$INFO" | json_get "d.get('password_field','')")
            RF_BOOT_TARGET=$(printf '%s' "$INFO" | json_get "d.get('boot_target','') or '$RF_BOOT_TARGET'")
            [ -z "$RF_MGMT_IP" ] && RF_MGMT_IP=$(printf '%s' "$INFO" | json_get "d.get('mgmt_ip','')")
            [ -z "$RF_ISO_URL" ] && RF_ISO_URL=$(printf '%s' "$INFO" | json_get "d.get('iso_url','')")
        fi
    fi

    if [ -z "$RF_BMC_URL" ]; then
        if [ ! -f "$TF_DIR/terraform.tfstate" ]; then
            echo "ERROR: no terraform state in $TF_DIR — run 'make init && make isos' first, or set REDFISH_BMC_URL" >&2
        else
            echo "ERROR: no BMC address for node '$node' (add bmc to var.nodes, apply, or set REDFISH_BMC_URL)" >&2
        fi
        exit 1
    fi
    RF_USER="${RF_USER:-root}"
    RF_PASSWORD_FIELD="${RF_PASSWORD_FIELD:-bmc_${node}_password}"
    [ -n "$RF_ISO_URL" ] || { echo "ERROR: no iso_url for node '$node' (set iso_http_base_url or REDFISH_ISO_URL)" >&2; exit 1; }
}

get_bmc_password() {
    if [ -n "${REDFISH_BMC_PASSWORD:-}" ]; then
        RF_PASSWORD="$REDFISH_BMC_PASSWORD"
        return 0
    fi
    : "${VAULT_ADDR:?VAULT_ADDR must be set to read the BMC password from Vault (or set REDFISH_BMC_PASSWORD)}"
    : "${VAULT_TOKEN:?VAULT_TOKEN must be set to read the BMC password from Vault (or set REDFISH_BMC_PASSWORD)}"
    RF_PASSWORD=$(curl -sS --max-time 15 \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "${VAULT_ADDR%/}/v1/${VAULT_KV_MOUNT:-kv}/data/${VAULT_SECRET_PATH:-proxmox-tf/cluster}" \
        | json_get "d['data']['data']['$RF_PASSWORD_FIELD']")
    [ -n "$RF_PASSWORD" ] || { echo "ERROR: Vault field '$RF_PASSWORD_FIELD' is empty" >&2; exit 1; }
}


# --- redfish plumbing --------------------------------------------------------
rf() { # rf <method> <path> [json-body]; RF_HTTP_CODE + RF_BODY are set
    local method="$1" path="$2" body="${3:-}" out code
    RF_HTTP_CODE=""
    RF_BODY=""
    local -a args=(-sS --max-time 60 -X "$method" -w $'\n%{http_code}')
    args=("${args[@]}" ${CURL_TLS[@]+"${CURL_TLS[@]}"} ${RF_AUTH_ARGS[@]+"${RF_AUTH_ARGS[@]}"})
    if [ -n "$body" ]; then
        args=("${args[@]}" -H 'Content-Type: application/json' -d "$body")
    fi
    out=$(curl "${args[@]}" "$RF_BMC_URL$path")
    code=$(printf '%s' "$out" | tail -n1)
    RF_HTTP_CODE=$code
    RF_BODY="${out%$'\n'*}"
    printf '%s' "$RF_BODY"
}

rf_auth_init() {
    if [ "${REDFISH_AUTH_MODE:-auto}" = "basic" ]; then
        RF_AUTH_ARGS=(-u "$RF_USER:$RF_PASSWORD")
        return 0
    fi
    # Redfish session auth; falls back to basic auth when unsupported.
    local resp code token
    resp=$(curl -sS "${CURL_TLS[@]}" --max-time 30 -X POST \
        -H 'Content-Type: application/json' \
        -d "$(python3 -c 'import json,sys; print(json.dumps({"UserName": sys.argv[1], "Password": sys.argv[2]}))' "$RF_USER" "$RF_PASSWORD")" \
        -D /tmp/rf-headers.$$ \
        -w $'\n%{http_code}' \
        "$RF_BMC_URL/redfish/v1/SessionService/Sessions")
    code=$(printf '%s' "$resp" | tail -n1)
    token=$(grep -i '^x-auth-token:' /tmp/rf-headers.$$ 2>/dev/null | head -n1 | awk '{print $2}' | tr -d '\r')
    rm -f /tmp/rf-headers.$$
    if { [ "$code" = "200" ] || [ "$code" = "201" ]; } && [ -n "$token" ]; then
        RF_AUTH_ARGS=(-H "X-Auth-Token: $token")
        return 0
    fi
    echo "redfish session auth unavailable (HTTP $code), falling back to basic auth"
    RF_AUTH_ARGS=(-u "$RF_USER:$RF_PASSWORD")
}

rf_check() { # rf_check <expected codes> — abort unless RF_HTTP_CODE matches
    case "$RF_HTTP_CODE" in
        $1) return 0 ;;
    esac
    echo "ERROR: redfish call returned HTTP $RF_HTTP_CODE: $RF_BODY" >&2
    exit 1
}

rf_patch() { # PATCH with automatic If-Match/ETag retry (some BMCs require it)
    local url="$1" body="$2" etag out
    rf PATCH "$url" "$body" > /dev/null
    case "$RF_HTTP_CODE" in
        200|204) return 0 ;;
    esac
    # Retry once with the resource's ETag in an If-Match header.
    etag=$(curl -sS "${CURL_TLS[@]}" --max-time 60 ${RF_AUTH_ARGS[@]+"${RF_AUTH_ARGS[@]}"} -D - -o /dev/null "$RF_BMC_URL$url" | grep -i '^etag:' | head -n1 | sed 's/^[Ee][Tt][Aa][Gg]:[[:space:]]*//' | tr -d '\r')
    if [ -n "$etag" ]; then
        out=$(curl -sS "${CURL_TLS[@]}" --max-time 60 -X PATCH ${RF_AUTH_ARGS[@]+"${RF_AUTH_ARGS[@]}"} \
            -H 'Content-Type: application/json' -H "If-Match: $etag" \
            -w $'\n%{http_code}' -d "$body" "$RF_BMC_URL$url")
        RF_HTTP_CODE=$(printf '%s' "$out" | tail -n1)
        RF_BODY="${out%$'\n'*}"
    fi
    case "$RF_HTTP_CODE" in
        200|204) return 0 ;;
    esac
    echo "ERROR: PATCH $url returned HTTP $RF_HTTP_CODE: $RF_BODY" >&2
    exit 1
}


rf_system_url() {
    rf GET /redfish/v1/Systems > /dev/null
    rf_check "200"
    printf '%s' "$RF_BODY" | json_get "d['Members'][0]['@odata.id']"
}

rf_system_power() {
    local url
    url=$(rf_system_url)
    rf GET "$url" > /dev/null
    rf_check "200"
    printf '%s' "$RF_BODY" | json_get "d['PowerState']"
}

rf_first_manager() {
    rf GET /redfish/v1/Managers > /dev/null
    rf_check "200"
    printf '%s' "$RF_BODY" | json_get "d['Members'][0]['@odata.id']"
}

rf_cd_virtual_media_url() { # first CD/DVD-capable virtual media device
    local mgr member media_ok
    mgr=$(rf_first_manager)
    for member in $(rf GET "$mgr/VirtualMedia" | python3 -c 'import json,sys; [print(m["@odata.id"]) for m in json.load(sys.stdin)["d"]["Members"]]' 2>/dev/null || true); do
        rf GET "$member" > /dev/null
        rf_check "200"
        media_ok=$(printf '%s' "$RF_BODY" | python3 -c 'import json,sys
d = json.load(sys.stdin)
types = d.get("MediaTypes") or []
print("yes" if any(t in ("CD", "DVD") for t in types) else "no")')
        if [ "$media_ok" = "yes" ]; then
            printf '%s' "$member"
            return 0
        fi
    done
    echo "" # none found
}

node_provisioned() {
    curl -sk --max-time 5 -o /dev/null "https://$1:8006/" 2>/dev/null
}


# --- commands ----------------------------------------------------------------
CMD="${1:-}"
NODE="${2:-}"

case "$CMD" in
    status)
        get_node_info "$NODE"; get_bmc_password; rf_auth_init
        rf_system_power
        ;;
    power)
        ACTION="${3:?usage: node-redfish.sh power <node> <On|ForceOff|GracefulShutdown|ForceRestart|GracefulRestart>}"
        get_node_info "$NODE"; get_bmc_password; rf_auth_init
        SYS=$(rf_system_url)
        rf POST "$SYS/Actions/ComputerSystem.Reset" "{\"ResetType\": \"$ACTION\"}" > /dev/null
        rf_check "200|204"
        echo "[$NODE] power action '$ACTION' accepted"
        ;;
    eject)
        get_node_info "$NODE"; get_bmc_password; rf_auth_init
        VM_URL=$(rf_cd_virtual_media_url)
        [ -n "$VM_URL" ] || { echo "ERROR: no CD/DVD virtual media device found" >&2; exit 1; }
        rf_patch "$VM_URL" '{"Inserted": false}' > /dev/null
        echo "[$NODE] virtual media ejected"
        ;;
    wait)
        get_node_info "$NODE"
        [ -n "$RF_MGMT_IP" ] || { echo "ERROR: no management IP known for node '$NODE' (set REDFISH_MGMT_IP or run the bootstrap apply)" >&2; exit 1; }
        TIMEOUT="${REDFISH_WAIT_TIMEOUT:-3600}"
        echo "[$NODE] waiting up to ${TIMEOUT}s for the PVE API at $RF_MGMT_IP:8006"
        START=$(date +%s)
        until node_provisioned "$RF_MGMT_IP"; do
            NOW=$(date +%s)
            [ $((NOW - START)) -ge "$TIMEOUT" ] && { echo "[$NODE] ERROR: node did not come up within ${TIMEOUT}s" >&2; exit 1; }
            sleep 15
        done
        echo "[$NODE] PVE API is up (installation finished) after $(( $(date +%s) - START ))s"
        ;;
    "")
        sed -n '/^# Usage:/,/^set -euo/p' "$0" >&2
        exit 1
        ;;
    *)
        echo "ERROR: unknown command '$CMD'" >&2
        sed -n '/^# Usage:/,/^set -euo/p' "$0" >&2
        exit 1
        ;;
esac
