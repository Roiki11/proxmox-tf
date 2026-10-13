locals {
  build_dir      = trimsuffix(var.build_dir, "/")
  base_iso_path  = coalesce(var.pve_iso_path, "${local.build_dir}/base/proxmox-ve.iso")
  remote_id      = coalesce(var.pdm_remote_id, var.cluster_name)
  bootstrap_node = var.bootstrap_node != "" ? var.bootstrap_node : sort(keys(var.nodes))[0]

  # Secrets fetched from the Vault KV-v2 secret (see vault.tf for the fields).
  # Optional fields default to an empty string; required ones are enforced by
  # lifecycle preconditions (answers.tf, pdm.tf).
  cluster_secrets = data.vault_kv_secret_v2.cluster.data
  # Root password, escaped for TOML basic strings (backslash first, then double
  # quotes) and for POSIX shell single-quoted strings.
  root_password_toml = replace(replace(lookup(local.cluster_secrets, "root_password", ""), "\\", "\\\\"), "\"", "\\\"")
  root_password_sh   = "'${replace(lookup(local.cluster_secrets, "root_password", ""), "'", "'\\''")}'"

  # PVE API credentials (password falls back to the root password).
  pve_password  = lookup(local.cluster_secrets, "pve_password", "") != "" ? lookup(local.cluster_secrets, "pve_password", "") : lookup(local.cluster_secrets, "root_password", "")
  pve_api_token = lookup(local.cluster_secrets, "pve_api_token", "")

  # Node definitions with node_defaults merged in (per-node values win).
  merged_nodes = {
    for name, node in var.nodes : name => {
      address         = element(split("/", node.management_cidr), 0)
      management_cidr = node.management_cidr
      gateway         = node.gateway != null ? node.gateway : var.node_defaults.gateway
      dns_server      = node.dns_server != null ? node.dns_server : var.node_defaults.dns_server
      dhcp            = coalesce(node.dhcp, var.node_defaults.dhcp)
      nic_filter      = coalesce(node.nic_filter, var.node_defaults.nic_filter, {})
      disks           = coalesce(node.disks, var.node_defaults.disks, [])
      disk_filter     = coalesce(node.disk_filter, var.node_defaults.disk_filter, {})
      filter_match    = coalesce(node.filter_match, var.node_defaults.filter_match, "any")
      filesystem      = coalesce(node.filesystem, var.node_defaults.filesystem, "ext4")
      zfs_raid        = node.zfs_raid != null ? node.zfs_raid : var.node_defaults.zfs_raid
      zfs_ashift      = node.zfs_ashift != null ? node.zfs_ashift : var.node_defaults.zfs_ashift
      zfs_arc_max     = node.zfs_arc_max != null ? node.zfs_arc_max : var.node_defaults.zfs_arc_max
      lvm_hdsize      = node.lvm_hdsize != null ? node.lvm_hdsize : var.node_defaults.lvm_hdsize
      lvm_swapsize    = node.lvm_swapsize != null ? node.lvm_swapsize : var.node_defaults.lvm_swapsize
      timezone        = coalesce(node.timezone, var.node_defaults.timezone, "UTC")
      fqdn            = "${name}.${var.cluster_domain}"
    }
  }

  answer_contents = {
    for name, node in local.merged_nodes : name => templatefile("${path.module}/templates/answer.toml.tftpl", {
      keyboard                 = var.keyboard
      country                  = var.country
      fqdn                     = node.fqdn
      timezone                 = node.timezone
      mailto                   = var.mailto != null ? var.mailto : ""
      root_password            = local.root_password_toml
      root_password_hashed     = lookup(local.cluster_secrets, "root_password_hashed", "")
      root_ssh_keys            = var.root_ssh_keys
      subscription_key         = lookup(local.cluster_secrets, "subscription_key", "")
      reboot_on_error          = var.reboot_on_error
      network_dhcp             = node.dhcp
      network_cidr             = node.management_cidr
      network_gateway          = node.gateway != null ? node.gateway : ""
      network_dns              = node.dns_server != null ? node.dns_server : ""
      network_filter           = node.nic_filter
      filesystem               = node.filesystem
      disk_list                = node.disks
      disk_filter              = node.disk_filter
      filter_match             = node.filter_match
      zfs_raid                 = node.zfs_raid != null ? node.zfs_raid : ""
      zfs_ashift               = coalesce(node.zfs_ashift, 0)
      zfs_arc_max              = coalesce(node.zfs_arc_max, 0)
      lvm_hdsize               = coalesce(node.lvm_hdsize, 0)
      lvm_swapsize             = coalesce(node.lvm_swapsize, 0)
      first_boot_enabled       = var.cluster_bootstrap_enabled
      first_boot_ordering      = "network-online"
      webhook_url              = var.post_installation_webhook != null && var.post_installation_webhook.url != null ? var.post_installation_webhook.url : ""
      webhook_cert_fingerprint = var.post_installation_webhook != null && var.post_installation_webhook.cert_fingerprint != null ? var.post_installation_webhook.cert_fingerprint : ""
      webhook_auth_token       = lookup(local.cluster_secrets, "post_installation_webhook_token", "")
    })
  }

  hook_contents = var.cluster_bootstrap_enabled ? {
    for name, node in local.merged_nodes : name => (
      name == local.bootstrap_node
      ? templatefile("${path.module}/templates/first-boot-leader.sh.tftpl", {
        cluster_name = var.cluster_name
        link0        = node.address
      })
      : templatefile("${path.module}/templates/first-boot-member.sh.tftpl", {
        bootstrap_address       = local.merged_nodes[local.bootstrap_node].address
        bootstrap_root_password = local.root_password_sh
        local_root_password     = local.root_password_sh
        my_ip                   = node.address
      })
    )
  } : {}

  answer_paths = {
    for name in keys(local.merged_nodes) :
    name => "${local.build_dir}/answers/${name}/answer.toml"
  }

  hook_paths = {
    for name in keys(local.hook_contents) :
    name => "${local.build_dir}/hooks/${name}/first-boot.sh"
  }

  iso_paths = {
    for name in keys(local.merged_nodes) :
    name => "${local.build_dir}/iso/${name}-auto.iso"
  }

  # Node addresses for the PDM remote registration.
  pdm_node_addresses = [
    for name, node in local.merged_nodes : node.address
  ]
}
