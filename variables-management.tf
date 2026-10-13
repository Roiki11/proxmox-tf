###############################################################################
# Proxmox VE connection (phase 2: live settings management)
#
# NOTE: no secrets live in configuration. The PVE API password/token are read
# from the Vault KV secret (see vault.tf for the expected fields).
###############################################################################

variable "pve_endpoint" {
  description = "API endpoint of the installed cluster (e.g. 'https://10.0.0.11:8006/'). Only contacted when manage_pve_resources is true."
  type        = string
  default     = ""
}

variable "pve_username" {
  description = "PVE API username (e.g. 'root@pam' or 'terraform@pve'). Its password/token comes from Vault."
  type        = string
  default     = "root@pam"
}

variable "pve_insecure" {
  description = "Skip TLS verification of the PVE API endpoint (self-signed certificates)."
  type        = bool
  default     = true
}

variable "manage_pve_resources" {
  description = "Toggle for phase 2. Set true once the nodes are installed, clustered and reachable at pve_endpoint, to manage datacenter settings, node TLS and register the cluster in PDM."
  type        = bool
  default     = false
}

variable "cluster_options" {
  description = "Proxmox VE datacenter (cluster) options, see https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/cluster_options."
  type = object({
    language       = optional(string)
    keyboard       = optional(string)
    email_from     = optional(string)
    console        = optional(string)
    mac_prefix     = optional(string)
    max_workers    = optional(number)
    migration_cidr = optional(string)
    migration_type = optional(string)
    http_proxy     = optional(string)
    next_id_lower  = optional(number)
    next_id_upper  = optional(number)
  })
  default = {}
}

variable "cluster_dns_servers" {
  description = "Additional DNS servers written to /etc/resolv.conf on every node (the per-node dns_server is always first)."
  type        = list(string)
  default     = []
}

###############################################################################
# Node TLS certificates (phase 2)
#
# Certificates are issued from a Vault PKI secret backend and installed on
# every node, replacing the default self-signed pveproxy certificate. The
# issuing CA can then be trusted by the Proxmox Datacenter Manager host, so
# remotes connect without TLS fingerprint pinning.
###############################################################################

variable "node_tls_enabled" {
  description = "Issue node certificates from Vault PKI and install them on the nodes (requires the cluster to be online)."
  type        = bool
  default     = false
}

variable "vault_pki_backend" {
  description = "Path of the PKI secret backend in Vault (e.g. 'pki_int')."
  type        = string
  default     = "pki"
}

variable "vault_pki_role" {
  description = "Name of the PKI role used to issue node certificates. The role must allow the node FQDNs in allowed_domains (and ip_sans if used)."
  type        = string
  default     = "proxmox-node"
}

variable "vault_pki_ttl" {
  description = "TTL of the issued node certificates (Vault duration, e.g. '8760h' for one year)."
  type        = string
  default     = "8760h"
}

variable "vault_pki_exclude_cn_from_sans" {
  description = "Exclude the common name from the certificate SANs (CN is still the subject)."
  type        = bool
  default     = true
}

variable "vault_pki_auto_renew" {
  description = "Renew node certificates automatically shortly before expiry and reinstall them."
  type        = bool
  default     = true
}

variable "vault_pki_min_seconds_remaining" {
  description = "Renew a node certificate when less than this many seconds remain (default 7 days)."
  type        = number
  default     = 604800
}

###############################################################################
# HashiCorp Vault
###############################################################################

variable "vault_address" {
  description = "Vault API address. Leave empty to use the VAULT_ADDR environment variable."
  type        = string
  default     = ""
}

variable "vault_kv_mount" {
  description = "KV-v2 mount holding the cluster secrets."
  type        = string
  default     = "kv"
}

variable "vault_secrets_path" {
  description = "Path of the KV-v2 secret with the cluster credentials (see vault.tf for the expected fields)."
  type        = string
  default     = "proxmox-tf/cluster"
}

###############################################################################
# Proxmox Datacenter Manager (PDM) management via its REST API
#
# PDM API credentials are read from the Vault secret (fields 'pdm_password'
# or 'pdm_api_token'); no credentials live in configuration.
###############################################################################

variable "pdm_enabled" {
  description = "Register and manage this cluster as a remote in Proxmox Datacenter Manager via its REST API."
  type        = bool
  default     = false
}

variable "pdm_api_url" {
  description = "Base URL of the PDM REST API (e.g. 'https://pdm.example.com:8007')."
  type        = string
  default     = ""
}

variable "pdm_api_user" {
  description = "PDM API user used for ticket authentication (e.g. 'root@pam')."
  type        = string
  default     = "root@pam"
}

variable "pdm_api_insecure" {
  description = "Skip TLS verification of the PDM API endpoint (default self-signed certificate)."
  type        = bool
  default     = true
}

variable "pdm_api_ca_file" {
  description = "Optional CA bundle to verify the PDM API endpoint instead of skipping verification."
  type        = string
  default     = ""
}

variable "pdm_remote_id" {
  description = "Remote ID in PDM. Defaults to the cluster name."
  type        = string
  default     = ""
}

variable "pdm_remote_authid" {
  description = "Authid used by PDM to authenticate against the cluster (e.g. 'pdm@pve!pdm'). Defaults to the user/token pair created by this project, or the Vault field 'pdm_remote_authid'."
  type        = string
  default     = null
}

variable "pdm_user_id" {
  description = "PVE user id created for PDM (realm included)."
  type        = string
  default     = "pdm@pve"
}

variable "pdm_token_name" {
  description = "Name of the PVE API token created for the PDM user."
  type        = string
  default     = "pdm"
}

variable "pdm_acl_role" {
  description = "Role granted to the PDM user/token on '/'. PDM needs broad read access; Administrator is the safe default for full feature support."
  type        = string
  default     = "Administrator"
}

variable "pdm_web_url" {
  description = "Optional web UI URL stored on the PDM remote (e.g. 'https://pdm.example.com:8007')."
  type        = string
  default     = null
}

variable "pdm_verify_nodes" {
  description = "After registration, probe every node's TLS certificate through the PDM API (POST /remotes/remote/{id}/probe-certificate) to verify connectivity."
  type        = bool
  default     = true
}

variable "pdm_delete_token_on_destroy" {
  description = "Delete the remote's API token on the cluster when the remote is removed from PDM."
  type        = bool
  default     = true
}
