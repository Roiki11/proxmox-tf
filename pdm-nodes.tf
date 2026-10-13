# Phase 3: applies node configuration through the PDM REST API
# (scripts/manage-pdm-node.sh --apply-node), driven by var.pdm_node_config.
#
# The proxied PDM node endpoints only expose writes for the APT database
# update and node firewall options; everything else (network, subscription,
# power) stays read-only through PDM and is managed on PVE directly.

locals {
  # Null-safe request payloads per node (nulls are omitted by the script).
  pdm_node_config_bodies = {
    for name, cfg in var.pdm_node_config : name => {
      apt_update = cfg.apt_update
      firewall_options = cfg.firewall_options != null ? {
        for key, value in cfg.firewall_options : key => value if value != null
      } : null
    }
  }
}

resource "terraform_data" "pdm_node_config" {
  for_each = var.pdm_enabled ? var.pdm_node_config : {}

  # Change detection (destroy provisioners may only reference self).
  input = jsonencode({
    node      = each.key
    remote_id = local.remote_id
    config    = local.pdm_node_config_bodies[each.key]
  })

  triggers_replace = [
    var.pdm_api_url,
    local.remote_id,
    sha512(jsonencode(local.pdm_node_config_bodies[each.key])),
    sha512("${local.pdm_api_token}:${var.pdm_api_user}:${local.pdm_api_password}"),
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/manage-pdm-node.sh --apply-node ${each.key}"

    environment = {
      PDM_API_URL      = element(self.triggers_replace, 0)
      PDM_API_USER     = var.pdm_api_user
      PDM_API_PASSWORD = local.pdm_api_password
      PDM_API_TOKEN    = local.pdm_api_token
      PDM_API_INSECURE = tostring(var.pdm_api_insecure)
      PDM_API_CA_FILE  = var.pdm_api_ca_file
      PDM_REMOTE_ID    = element(self.triggers_replace, 1)
      PDM_NODE_CONFIG  = jsonencode(local.pdm_node_config_bodies[each.key])
    }
  }

  # Node configuration is not reversible via the API (an APT database update
  # cannot be undone and firewall options are not reverted) — nothing to do
  # on destroy.

  # The remote must be registered before nodes can be managed through it.
  depends_on = [terraform_data.pdm_remote]

  lifecycle {
    precondition {
      condition     = contains(keys(var.nodes), each.key)
      error_message = format("pdm_node_config key '%s' is not a node of var.nodes", each.key)
    }

    precondition {
      condition     = local.pdm_credential_ready
      error_message = "The Vault secret must contain 'pdm_password' (for var.pdm_api_user) or 'pdm_api_token' to authenticate against the PDM REST API."
    }
  }
}
