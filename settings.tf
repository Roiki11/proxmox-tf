# Phase 2: manages datacenter-wide settings and per-node basic settings on the
# installed (clustered) Proxmox VE. Gated by var.manage_pve_resources so the
# bootstrap phase (ISO generation) can run before any PVE instance exists.

locals {
  managed_nodes = var.manage_pve_resources ? local.merged_nodes : {}
}

data "proxmox_virtual_environment_nodes" "all" {
  count = var.manage_pve_resources ? 1 : 0
}

resource "proxmox_cluster_options" "this" {
  count = var.manage_pve_resources ? 1 : 0

  language       = try(var.cluster_options.language, null)
  keyboard       = try(var.cluster_options.keyboard, null)
  email_from     = try(var.cluster_options.email_from, null)
  console        = try(var.cluster_options.console, null)
  mac_prefix     = try(var.cluster_options.mac_prefix, null)
  max_workers    = try(var.cluster_options.max_workers, null)
  migration_cidr = try(var.cluster_options.migration_cidr, null)
  migration_type = try(var.cluster_options.migration_type, null)
  http_proxy     = try(var.cluster_options.http_proxy, null)

  next_id = try(var.cluster_options.next_id_lower, null) != null || try(var.cluster_options.next_id_upper, null) != null ? {
    lower = try(var.cluster_options.next_id_lower, null)
    upper = try(var.cluster_options.next_id_upper, null)
  } : null
}

resource "proxmox_virtual_environment_time" "nodes" {
  for_each = local.managed_nodes

  node_name = each.key
  time_zone = each.value.timezone
}

resource "proxmox_virtual_environment_dns" "nodes" {
  for_each = local.managed_nodes

  node_name = each.key
  domain    = var.cluster_domain

  servers = compact(concat(
    [(each.value.dns_server != null ? each.value.dns_server : "")],
    var.cluster_dns_servers
  ))
}

# Writes /etc/hosts on every node so cluster members resolve each other by
# name, plus a loopback entry. Referencing nodes by IP is recommended for
# corosync, this only helps SSH/CLI ergonomics.
resource "proxmox_virtual_environment_hosts" "nodes" {
  for_each = local.managed_nodes

  node_name = each.key

  entry {
    address   = "127.0.0.1"
    hostnames = ["localhost"]
  }

  dynamic "entry" {
    for_each = local.merged_nodes
    iterator = node
    content {
      address = node.value.address
      hostnames = [
        node.value.fqdn,
        node.key,
      ]
    }
  }
}

# Installs the Vault PKI-issued certificate on every node, replacing the
# default self-signed pveproxy certificate. The pveproxy service is restarted
# by PVE automatically. Clients (including PDM) verify against the issuing CA:
# trust the Vault CA on the PDM host (system trust store) instead of pinning
# fingerprints.
resource "proxmox_virtual_environment_certificate" "node" {
  for_each = var.node_tls_enabled ? local.managed_nodes : {}

  node_name = each.key

  certificate       = vault_pki_secret_backend_cert.node[each.key].certificate
  certificate_chain = length(vault_pki_secret_backend_cert.node[each.key].ca_chain) > 0 ? join("\n", vault_pki_secret_backend_cert.node[each.key].ca_chain) : vault_pki_secret_backend_cert.node[each.key].issuing_ca
  private_key       = vault_pki_secret_backend_cert.node[each.key].private_key

  # Replace the default (or a previously provisioned) certificate. Renewals
  # from vault_pki_secret_backend_cert auto-renewal propagate automatically.
  overwrite = true

  depends_on = [
    proxmox_virtual_environment_time.nodes,
    proxmox_virtual_environment_dns.nodes,
  ]
}
