###############################################################################
# Secrets from HashiCorp Vault — no secrets live in the Terraform/OpenTofu
# configuration or .tfvars files.
#
# The KV-v2 secret at var.vault_kv_mount / var.vault_secrets_path provides:
#
#   root_password                  (string) root password of all installed nodes;
#                                  required when cluster_bootstrap_enabled = true
#   root_password_hashed           (string, optional) alternative to root_password
#                                  for standalone installs (no join automation)
#   pve_password                   (string, optional) PVE API password; falls back
#                                  to root_password
#   pve_api_token                  (string, optional) PVE API token
#                                  ('user@realm!id=secret'); takes precedence
#   subscription_key               (string, optional) Proxmox subscription key
#   post_installation_webhook_token
#                                  (string, optional) bearer token for the
#                                  post-installation webhook
#   pdm_password                   (string) PDM API password for pdm_api_user;
#                                  required when pdm_enabled = true and no
#                                  pdm_api_token is present
#   pdm_api_token                  (string, optional) PDM API token
#                                  ('user@realm!id=secret'); takes precedence
#   pdm_remote_token               (string, optional) pre-existing PVE API token
#                                  secret used to register the remote; when set,
#                                  this project does not create a user/token
#   pdm_remote_authid              (string, optional) authid matching pdm_remote_token
#
# The Vault provider authenticates with VAULT_ADDR / VAULT_TOKEN (or any
# auth_login_* block you add in providers.tf) — never with tfvars.
###############################################################################

data "vault_kv_secret_v2" "cluster" {
  mount = var.vault_kv_mount
  name  = var.vault_secrets_path
}

###############################################################################
# Node TLS certificates from the Vault PKI secret backend.
# Uploaded to the nodes by proxmox_virtual_environment_certificate (settings.tf).
###############################################################################

resource "vault_pki_secret_backend_cert" "node" {
  for_each = var.node_tls_enabled ? var.nodes : {}

  backend     = var.vault_pki_backend
  name        = var.vault_pki_role
  common_name = "${each.key}.${var.cluster_domain}"
  ip_sans     = [element(split("/", each.value.management_cidr), 0)]

  ttl    = var.vault_pki_ttl
  format = "pem"
  # The resource only supports "der" | "pkcs8"; pkcs8 returns a PEM-encoded
  # PKCS#8 private key, which is what the PVE certificate API expects.
  private_key_format   = "pkcs8"
  exclude_cn_from_sans = var.vault_pki_exclude_cn_from_sans

  auto_renew            = var.vault_pki_auto_renew
  min_seconds_remaining = var.vault_pki_min_seconds_remaining
}
