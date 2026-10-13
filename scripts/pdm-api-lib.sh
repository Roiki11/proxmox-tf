#!/usr/bin/env bash
# Shared helpers for talking to the Proxmox Datacenter Manager REST API.
#
# Sourced by register-pdm-remote.sh and manage-pdm-node.sh. Not executable.
#
# Environment:
#   PDM_API_URL       base URL, e.g. https://pdm.example.com:8007
#   PDM_API_USER      user@realm for ticket auth
#   PDM_API_PASSWORD  password for PDM_API_USER
#   PDM_API_TOKEN     optional 'user@realm!id=secret' API token; takes
#                     precedence over user/password
#   PDM_API_INSECURE  1 to skip TLS verification (default self-signed cert)
#   PDM_API_CA_FILE   optional CA bundle for verification instead
#
# In --remove/destroy contexts (pdm.tf destroy provisioner) all inputs arrive
# as a JSON blob in PDM_CONFIG and are unpacked here.
#
# Provides: pdm_config_unpack, pdm_auth_init, pdm_api, pdm_api_quiet,
# pdm_remote_exists. After pdm_auth_init, PDM_AUTH holds the curl auth args.

pdm_config_unpack() {
    # Unpack the JSON blob passed by the destroy provisioner into the
    # regular environment variables.
    [ -z "${PDM_CONFIG:-}" ] && return 0
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
}

pdm_auth_init() {
    [ -n "${PDM_CONFIG:-}" ] && pdm_config_unpack

    PDM_BASE_URL="${PDM_API_URL%/}"
    PDM_BASE_URL="${PDM_BASE_URL:?PDM_API_URL must be set, e.g. https://pdm.example.com:8007}"

    PDM_CURL_TLS=()
    if [ -n "${PDM_API_CA_FILE:-}" ]; then
        PDM_CURL_TLS=(--cacert "$PDM_API_CA_FILE")
    elif [ "${PDM_API_INSECURE:-1}" = "1" ]; then
        PDM_CURL_TLS=(-k)
    fi

    PDM_AUTH=()
    if [ -n "${PDM_API_TOKEN:-}" ]; then
        PDM_AUTH=(-H "Authorization: PVEAPITicket=$PDM_API_TOKEN")
        return 0
    fi

    PDM_COOKIE_JAR=$(mktemp)
    trap 'rm -f "${PDM_COOKIE_JAR:-}"' EXIT

    RESP=$(curl -sS ${PDM_CURL_TLS[@]+"${PDM_CURL_TLS[@]}"} --max-time 30 \
        -c "$PDM_COOKIE_JAR" \
        -H 'Content-Type: application/json' \
        -d "$(python3 -c 'import json,sys; print(json.dumps({"username": sys.argv[1], "password": sys.argv[2]}))' "${PDM_API_USER:-root@pam}" "${PDM_API_PASSWORD:-}")" \
        "$PDM_BASE_URL/api2/json/access/ticket")

    TICKET=$(printf '%s' "$RESP" | pdm_json_get "d['data']['ticket']")
    CSRF=$(printf '%s' "$RESP" | pdm_json_get "d['data']['CSRFPreventionToken']")
    if [ -z "$TICKET" ]; then
        echo "ERROR: could not authenticate against $PDM_BASE_URL" >&2
        echo "$RESP" >&2
        exit 1
    fi

    PDM_AUTH=(-b "$PDM_COOKIE_JAR" -H "CSRFPreventionToken: $CSRF")
}

pdm_json_get() { # pdm_json_get <python expression over 'd'>
    python3 -c "import json,sys
d = json.load(sys.stdin)
print(eval(sys.argv[1]))" "$1"
}

pdm_api() { # pdm_api <method> <path> [json-body]
    local method="$1" path="$2" body="${3:-}" code out
    local args=(curl -sS ${PDM_CURL_TLS[@]+"${PDM_CURL_TLS[@]}"} --max-time 60 -X "$method" ${PDM_AUTH[@]+"${PDM_AUTH[@]}"} -w $'\n%{http_code}' -H 'Content-Type: application/json')
    [ -n "$body" ] && args+=(-d "$body")
    out=$("${args[@]}" "$PDM_BASE_URL/api2/json$path")
    code=$(printf '%s' "$out" | tail -n1)
    [ "$code" = "200" ] || { echo "ERROR: $method $path returned HTTP $code: ${out%$'\n'*}" >&2; exit 1; }
    printf '%s' "${out%$'\n'*}"
}

pdm_api_quiet() { # like pdm_api but discards the response body
    pdm_api "$@" >/dev/null
}

pdm_remote_exists() { # pdm_remote_exists <id>
    pdm_api GET /remotes/remote | python3 -c 'import json,sys
ids = [r["id"] for r in json.load(sys.stdin)["data"]]
print("yes" if sys.argv[1] in ids else "no")' "$1"
}
