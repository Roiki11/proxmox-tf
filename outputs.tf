output "bootstrap_node" {
  description = "Node that creates the cluster on first boot."
  value       = local.bootstrap_node
}

output "node_isos" {
  description = "Automated-installation ISO per node (write to USB/PXE/VM boot)."
  value       = local.iso_paths
}

output "node_answer_files" {
  description = "Rendered answer.toml per node (kept for reference/validation)."
  value       = local.answer_paths
}

output "node_first_boot_hooks" {
  description = "First-boot hook scripts embedded in the ISOs."
  value       = local.hook_paths
}

output "installation_instructions" {
  description = "What to do after 'make isos'."
  value = [
    "1. Write each node's ISO from output.node_isos to installation media or boot it on the machine (USB/PXE/iKVM).",
    "2. The installer runs unattended; nodes reboot when done.",
    "3. On first boot the leader creates the cluster and members join automatically (cluster_bootstrap_enabled = true).",
    "4. Verify with: ssh root@<bootstrap-node-ip> 'pvecm status'",
    "5. Then set manage_pve_resources = true (and pdm_enabled = true to register in PDM) and apply again.",
  ]
}

output "pve_nodes" {
  description = "Nodes discovered via the PVE API (only when manage_pve_resources = true)."
  value = var.manage_pve_resources ? {
    names  = data.proxmox_virtual_environment_nodes.all[0].names
    online = data.proxmox_virtual_environment_nodes.all[0].online
  } : null
}

output "pdm_remote_id" {
  description = "Remote ID under which the cluster is registered in PDM."
  value       = var.pdm_enabled ? local.remote_id : null
}

output "node_certificates" {
  description = "Vault-issued TLS certificate fingerprint/expiration per node (only when node_tls_enabled and manage_pve_resources are true)."
  value = var.node_tls_enabled && var.manage_pve_resources ? {
    for name, cert in proxmox_virtual_environment_certificate.node : name => {
      ssl_fingerprint = cert.ssl_fingerprint
      expiration_date = cert.expiration_date
      subject         = cert.subject
    }
  } : null
}

output "secrets_source" {
  description = "Location of the Vault KV-v2 secret holding the cluster credentials (values are not exposed)."
  value = {
    address = var.vault_address != "" ? var.vault_address : "$VAULT_ADDR"
    mount   = var.vault_kv_mount
    path    = var.vault_secrets_path
  }
}

output "pdm_authid" {
  description = "Authid PDM uses to authenticate against this cluster."
  value       = var.pdm_enabled ? local.pdm_authid : null
  sensitive   = true
}


output "node_bmcs" {
  description = "BMC/Redfish connection info per node (no passwords — BMC passwords come from the Vault fields shown in password_field)."
  value = {
    for name, node in var.nodes : name => node.bmc != null ? {
      address        = node.bmc.address
      username       = node.bmc.username
      password_field = node.bmc.password_vault_field != null ? node.bmc.password_vault_field : "bmc_${name}_password"
      boot_target    = node.bmc.boot_target
      mgmt_ip        = element(split("/", node.management_cidr), 0)
      iso_url        = var.iso_http_base_url != "" ? "${var.iso_http_base_url}/${name}-auto.iso" : ""
    } : null
  }
}
