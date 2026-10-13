provider "proxmox" {
  # Falls back to a placeholder endpoint/credentials while bootstrap-only
  # (manage_pve_resources = false), so provider configuration succeeds without
  # a live cluster. Nothing is ever contacted in that phase because all
  # provider resources/data sources are gated off via var.manage_pve_resources.
  # Real credentials come from Vault (vault.tf).
  endpoint = var.pve_endpoint != "" ? var.pve_endpoint : "https://localhost:8006/"

  username  = var.pve_username
  password  = local.pve_password
  api_token = local.pve_api_token != "" ? local.pve_api_token : null

  # Most lab setups use the default self-signed certificate.
  insecure = var.pve_insecure
}

# Authentication to Vault is deliberately left to the provider's environment
# conventions so no tokens live in configuration: VAULT_ADDR + VAULT_TOKEN
# (or one of the provider's auth_login_* blocks if you extend this file).
provider "vault" {
  address = var.vault_address != "" ? var.vault_address : null
}

provider "local" {}
