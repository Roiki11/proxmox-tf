# Network-backed storages (NFS/CIFS/PBS); see storage.tf for the local ones.

resource "proxmox_storage_nfs" "storage" {
  for_each = var.manage_pve_resources ? var.storage_nfs : {}

  id    = each.key
  nodes = each.value.nodes

  server                   = each.value.server
  export                   = each.value.export
  content                  = each.value.content
  disable                  = each.value.disable
  options                  = each.value.options
  preallocation            = each.value.preallocation
  snapshot_as_volume_chain = each.value.snapshot_as_volume_chain
  create_base_path         = each.value.create_base_path
  create_subdirs           = each.value.create_subdirs

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

resource "proxmox_storage_cifs" "storage" {
  for_each = var.manage_pve_resources ? var.storage_cifs : {}

  id    = each.key
  nodes = each.value.nodes

  server                   = each.value.server
  share                    = each.value.share
  username                 = each.value.username
  password                 = local.cifs_passwords[each.key]
  content                  = each.value.content
  disable                  = each.value.disable
  domain                   = each.value.domain
  subdirectory             = each.value.subdirectory
  options                  = each.value.options
  preallocation            = each.value.preallocation
  snapshot_as_volume_chain = each.value.snapshot_as_volume_chain
  create_base_path         = each.value.create_base_path
  create_subdirs           = each.value.create_subdirs

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

  lifecycle {
    precondition {
      condition     = local.cifs_passwords[each.key] != ""
      error_message = format("The Vault secret field '%s' must contain the SMB/CIFS password for storage '%s'", each.value.password_vault_field != null ? each.value.password_vault_field : "storage_${each.key}_password", each.key)
    }
  }
}

resource "proxmox_storage_pbs" "storage" {
  for_each = var.manage_pve_resources ? var.storage_pbs : {}

  id    = each.key
  nodes = each.value.nodes

  server                  = each.value.server
  datastore               = each.value.datastore
  username                = each.value.username
  password                = local.pbs_passwords[each.key]
  fingerprint             = each.value.fingerprint
  content                 = each.value.content
  namespace               = each.value.namespace
  disable                 = each.value.disable
  generate_encryption_key = coalesce(each.value.generate_encryption_key, false)

  # Conflicts with generate_encryption_key: only pass an existing key when the
  # provider is not asked to generate one.
  encryption_key = coalesce(each.value.generate_encryption_key, false) ? null : (local.pbs_encryption_keys[each.key] != "" ? local.pbs_encryption_keys[each.key] : null)

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

  lifecycle {
    precondition {
      condition     = local.pbs_passwords[each.key] != ""
      error_message = format("The Vault secret field '%s' must contain the PBS password for storage '%s'", each.value.password_vault_field != null ? each.value.password_vault_field : "storage_${each.key}_password", each.key)
    }
  }
}
