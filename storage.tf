# Storage definitions managed directly on the cluster (bpg/proxmox).
# Declared in variables-storage.tf; applied with `make pve-storage` or the
# regular apply flow. All resources are gated by var.manage_pve_resources.

locals {
  # CIFS/PBS credentials resolved from the Vault KV secret.
  cifs_passwords = {
    for id, cfg in var.storage_cifs : id => lookup(
      local.cluster_secrets,
      cfg.password_vault_field != null ? cfg.password_vault_field : "storage_${id}_password",
      "",
    )
  }
  pbs_passwords = {
    for id, cfg in var.storage_pbs : id => lookup(
      local.cluster_secrets,
      cfg.password_vault_field != null ? cfg.password_vault_field : "storage_${id}_password",
      "",
    )
  }
  pbs_encryption_keys = {
    for id, cfg in var.storage_pbs : id => lookup(
      local.cluster_secrets,
      cfg.encryption_key_vault_field != null ? cfg.encryption_key_vault_field : "storage_${id}_encryption_key",
      "",
    )
  }
}

resource "proxmox_storage_directory" "storage" {
  for_each = var.manage_pve_resources ? var.storage_directories : {}

  id    = each.key
  path  = each.value.path
  nodes = each.value.nodes

  content          = each.value.content
  shared           = each.value.shared
  disable          = each.value.disable
  create_base_path = each.value.create_base_path
  create_subdirs   = each.value.create_subdirs
  preallocation    = each.value.preallocation

  dynamic "backups" {
    for_each = each.value.backups != null ? [each.value.backups] : []
    iterator = b
    content {
      keep_all              = b.value.keep_all
      keep_last             = b.value.keep_last
      keep_hourly           = b.value.keep_hourly
      keep_daily            = b.value.keep_daily
      keep_weekly           = b.value.keep_weekly
      keep_monthly          = b.value.keep_monthly
      keep_yearly           = b.value.keep_yearly
      max_protected_backups = b.value.max_protected_backups
    }
  }
}

resource "proxmox_storage_lvm" "storage" {
  for_each = var.manage_pve_resources ? var.storage_lvm : {}

  id    = each.key
  nodes = each.value.nodes

  volume_group         = each.value.volume_group
  content              = each.value.content
  shared               = each.value.shared
  disable              = each.value.disable
  wipe_removed_volumes = each.value.wipe_removed_volumes
}

resource "proxmox_storage_lvmthin" "storage" {
  for_each = var.manage_pve_resources ? var.storage_lvmthin : {}

  id    = each.key
  nodes = each.value.nodes

  volume_group = each.value.volume_group
  thin_pool    = each.value.thin_pool
  content      = each.value.content
  disable      = each.value.disable
}

resource "proxmox_storage_zfspool" "storage" {
  for_each = var.manage_pve_resources ? var.storage_zfspool : {}

  id    = each.key
  nodes = each.value.nodes

  zfs_pool       = each.value.zfs_pool
  content        = each.value.content
  disable        = each.value.disable
  thin_provision = each.value.thin_provision
  blocksize      = each.value.blocksize
}
