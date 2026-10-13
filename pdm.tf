# Phase 3: registers the cluster as a remote in Proxmox Datacenter Manager
# through its REST API (/api2/json/remotes/remote*), no SSH required.
#
# PDM API authentication (ticket or API token) comes from the Vault secret:
#   pdm_password    -> ticket auth as var.pdm_api_user
#   pdm_api_token   -> 'user@realm!id=secret' token auth (takes precedence)
#
# The remote authenticates against the cluster with a PVE API token:
#   - by default this project creates a dedicated PVE user (var.pdm_user_id)
#     and API token (var.pdm_token_name) and grants var.pdm_acl_role on '/'
#   - alternatively provide the Vault fields pdm_remote_token (+ optional
#     pdm_remote_authid) to use a pre-existing token

locals {
  pdm_api_password        = lookup(local.cluster_secrets, "pdm_password", "")
  pdm_api_token           = lookup(local.cluster_secrets, "pdm_api_token", "")
  pdm_remote_token        = lookup(local.cluster_secrets, "pdm_remote_token", "")
  pdm_remote_authid_vault = lookup(local.cluster_secrets, "pdm_remote_authid", "")

  # PDM REST credentials (token wins over password).
  pdm_credential_ready = local.pdm_api_token != "" || (var.pdm_api_user != null && local.pdm_api_password != "")

  # Credentials the remote itself uses against the cluster.
  pdm_create_credentials = var.pdm_enabled && local.pdm_remote_token == ""

  pdm_authid = local.pdm_create_credentials ? "${var.pdm_user_id}!${var.pdm_token_name}" : (
    var.pdm_remote_authid != null ? var.pdm_remote_authid : local.pdm_remote_authid_vault
  )

  pdm_token_value = local.pdm_create_credentials ? try(proxmox_user_token.pdm[0].value, "") : local.pdm_remote_token
}

resource "proxmox_virtual_environment_user" "pdm" {
  count = local.pdm_create_credentials ? 1 : 0

  user_id = var.pdm_user_id
  comment = "Proxmox Datacenter Manager integration (managed by OpenTofu)"
  enabled = true
}

resource "proxmox_user_token" "pdm" {
  count = local.pdm_create_credentials ? 1 : 0

  user_id    = var.pdm_user_id
  token_name = var.pdm_token_name
  comment    = "Used by Proxmox Datacenter Manager to connect to this cluster"

  # Give the token the full privileges of the user; the ACL below scopes it.
  privileges_separation = false

  depends_on = [proxmox_virtual_environment_user.pdm]
}

resource "proxmox_acl" "pdm_user" {
  count = local.pdm_create_credentials ? 1 : 0

  user_id   = var.pdm_user_id
  path      = "/"
  role_id   = var.pdm_acl_role
  propagate = true

  depends_on = [proxmox_virtual_environment_user.pdm]
}

resource "terraform_data" "pdm_remote" {
  count = var.pdm_enabled ? 1 : 0

  # Destroy provisioners may only reference self/count.index/each.key, so all
  # values needed for remote removal travel through input -> self.output.
  input = jsonencode({
    api_url      = var.pdm_api_url
    api_user     = var.pdm_api_user
    api_password = local.pdm_api_password
    api_token    = local.pdm_api_token
    insecure     = tostring(var.pdm_api_insecure)
    ca_file      = var.pdm_api_ca_file
    remote_id    = local.remote_id
    delete_token = tostring(var.pdm_delete_token_on_destroy)
  })

  # Ordered list used for change detection of the registration:
  #   0: api url, 1: remote id, 2: delete-token-on-destroy, 3: authid,
  #   4: credential hash, 5: nodes hash, 6: web-url, 7: verify flag
  triggers_replace = [
    var.pdm_api_url,
    local.remote_id,
    tostring(var.pdm_delete_token_on_destroy),
    local.pdm_authid,
    sha512("${local.pdm_api_token}:${var.pdm_api_user}:${local.pdm_api_password}:${local.pdm_token_value}"),
    sha512(jsonencode(local.pdm_node_addresses)),
    (var.pdm_web_url != null ? var.pdm_web_url : ""),
    tostring(var.pdm_verify_nodes),
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/register-pdm-remote.sh"

    environment = {
      PDM_API_URL             = element(self.triggers_replace, 0)
      PDM_API_USER            = var.pdm_api_user
      PDM_API_PASSWORD        = local.pdm_api_password
      PDM_API_TOKEN           = local.pdm_api_token
      PDM_API_INSECURE        = tostring(var.pdm_api_insecure)
      PDM_API_CA_FILE         = var.pdm_api_ca_file
      REMOTE_ID               = element(self.triggers_replace, 1)
      REMOTE_TYPE             = "pve"
      AUTHID                  = element(self.triggers_replace, 3)
      TOKEN_SECRET            = local.pdm_token_value
      NODE_ADDRESSES          = jsonencode(local.pdm_node_addresses)
      WEB_URL                 = element(self.triggers_replace, 6)
      VERIFY_NODES            = element(self.triggers_replace, 7)
      DELETE_TOKEN_ON_DESTROY = element(self.triggers_replace, 2)
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/register-pdm-remote.sh --remove"

    environment = {
      PDM_CONFIG = self.output
    }
  }

  lifecycle {
    precondition {
      condition     = var.pdm_api_url != ""
      error_message = "pdm_api_url must be set when pdm_enabled is true (e.g. 'https://pdm.example.com:8007')."
    }

    precondition {
      condition     = local.pdm_credential_ready
      error_message = "The Vault secret must contain 'pdm_password' (for var.pdm_api_user) or 'pdm_api_token' to authenticate against the PDM REST API."
    }

    precondition {
      condition     = local.pdm_authid != "" && local.pdm_token_value != ""
      error_message = "PDM needs an authid and token to connect to the cluster: let the project create the PVE user/token, or provide the Vault fields pdm_remote_token / pdm_remote_authid."
    }
  }
}
