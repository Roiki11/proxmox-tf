#!/usr/bin/env bash
# External data source program (hashicorp/external) that reports whether a
# node is already provisioned: the PVE API (port 8006) on the node's
# management IP answers with any HTTP response (even 401).
#
# Input (stdin): JSON {"node": "<name>", "mgmt_ip": "<ip>"}
# Output: {"provisioned": "true"|"false"}
set -uo pipefail

query=$(cat)
MGMT_IP=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["mgmt_ip"])' <<<"$query" 2>/dev/null)

if [ -z "$MGMT_IP" ]; then
    # Malformed input from the external provider protocol — treat as unknown;
    # report unprovisioned=false so boot resources are created? No: safer to
    # report provisioned=true so an unprovisioned machine is not mistaken for
    # a reachable one? A missing mgmt_ip is a configuration error - surface it
    # through the error field which the external provider turns into a
    # Terraform error.
    echo '{"error": "mgmt_ip missing in query"}' >&2
    exit 1
fi

if curl -sk --max-time 5 -o /dev/null "https://$MGMT_IP:8006/" 2>/dev/null; then
    printf '{"provisioned": "true"}\n'
else
    printf '{"provisioned": "false"}\n'
fi
