###############################################################################
# Storage definitions managed directly on the cluster (bpg/proxmox).
#
# All maps are keyed by the storage ID. Every storage type is a separate
# variable; apply them with `make pve-storage` or the regular apply flow.
# All storages are gated by var.manage_pve_resources.
#
# Secrets: CIFS and PBS credentials come from the Vault KV secret using the
# field naming convention below (override with password_vault_field):
#   storage_<id>_password        CIFS/PBS password
#   storage_<id>_encryption_key  optional existing PBS encryption key
###############################################################################

variable "storage_directories" {
  description = "Directory-based storages. Fields: path (required), content (list: images, iso, backup, rootdir, vztmpl, snippets, import), nodes (list, empty = all nodes), shared, disable, create_base_path, create_subdirs, preallocation (metadata|off|full|fallocated), backups ({keep_last, keep_hourly, keep_daily, keep_weekly, keep_monthly, keep_yearly, keep_all, max_protected_backups})."
  type = map(object({
    path             = string
    content          = optional(list(string), ["images", "iso"])
    nodes            = optional(list(string), [])
    shared           = optional(bool)
    disable          = optional(bool)
    create_base_path = optional(bool)
    create_subdirs   = optional(bool)
    preallocation    = optional(string)
    backups = optional(object({
      keep_all              = optional(bool)
      keep_last             = optional(number)
      keep_hourly           = optional(number)
      keep_daily            = optional(number)
      keep_weekly           = optional(number)
      keep_monthly          = optional(number)
      keep_yearly           = optional(number)
      max_protected_backups = optional(number)
    }))
  }))
  default = {}
}

variable "storage_lvm" {
  description = "LVM storages. Fields: volume_group (required), content, nodes, shared, disable, wipe_removed_volumes."
  type = map(object({
    volume_group         = string
    content              = optional(list(string), ["images", "rootdir"])
    nodes                = optional(list(string), [])
    shared               = optional(bool)
    disable              = optional(bool)
    wipe_removed_volumes = optional(bool)
  }))
  default = {}
}

variable "storage_lvmthin" {
  description = "Thin LVM storages. Fields: volume_group, thin_pool (required), content, nodes, disable."
  type = map(object({
    volume_group = string
    thin_pool    = string
    content      = optional(list(string), ["images", "rootdir"])
    nodes        = optional(list(string), [])
    disable      = optional(bool)
  }))
  default = {}
}

variable "storage_zfspool" {
  description = "ZFS pool storages. Fields: zfs_pool (required, e.g. 'rpool/data'), content, nodes, disable, thin_provision, blocksize (e.g. '64k')."
  type = map(object({
    zfs_pool       = string
    content        = optional(list(string), ["images", "rootdir"])
    nodes          = optional(list(string), [])
    disable        = optional(bool)
    thin_provision = optional(bool)
    blocksize      = optional(string)
  }))
  default = {}
}


variable "storage_nfs" {
  description = "NFS storages. Fields: server, export (required), content, nodes, disable, options (e.g. 'vers=4.2'), preallocation, snapshot_as_volume_chain, backups (see storage_directories)."
  type = map(object({
    server                   = string
    export                   = string
    content                  = optional(list(string), ["images", "iso", "backup"])
    nodes                    = optional(list(string), [])
    disable                  = optional(bool)
    options                  = optional(string)
    preallocation            = optional(string)
    snapshot_as_volume_chain = optional(bool)
    create_base_path         = optional(bool)
    create_subdirs           = optional(bool)
    backups = optional(object({
      keep_all              = optional(bool)
      keep_last             = optional(number)
      keep_hourly           = optional(number)
      keep_daily            = optional(number)
      keep_weekly           = optional(number)
      keep_monthly          = optional(number)
      keep_yearly           = optional(number)
      max_protected_backups = optional(number)
    }))
  }))
  default = {}
}

variable "storage_cifs" {
  description = "SMB/CIFS storages. Fields: server, share, username (required), password_vault_field (optional override for the Vault field holding the SMB password, default 'storage_<id>_password'), content, nodes, disable, domain, subdirectory, options, preallocation, snapshot_as_volume_chain, backups."
  type = map(object({
    server                   = string
    share                    = string
    username                 = string
    password_vault_field     = optional(string)
    content                  = optional(list(string), ["images", "iso", "backup"])
    nodes                    = optional(list(string), [])
    disable                  = optional(bool)
    domain                   = optional(string)
    subdirectory             = optional(string)
    options                  = optional(string)
    preallocation            = optional(string)
    snapshot_as_volume_chain = optional(bool)
    create_base_path         = optional(bool)
    create_subdirs           = optional(bool)
    backups = optional(object({
      keep_all              = optional(bool)
      keep_last             = optional(number)
      keep_hourly           = optional(number)
      keep_daily            = optional(number)
      keep_weekly           = optional(number)
      keep_monthly          = optional(number)
      keep_yearly           = optional(number)
      max_protected_backups = optional(number)
    }))
  }))
  default = {}
}

variable "storage_pbs" {
  description = "Proxmox Backup Server storages. Fields: server, datastore, username (required), password_vault_field (optional override, default 'storage_<id>_password'), encryption_key_vault_field (optional, default 'storage_<id>_encryption_key'), fingerprint (optional PBS cert fingerprint), content, nodes, namespace, disable, generate_encryption_key, backups."
  type = map(object({
    server                     = string
    datastore                  = string
    username                   = string
    password_vault_field       = optional(string)
    encryption_key_vault_field = optional(string)
    fingerprint                = optional(string)
    content                    = optional(list(string), ["backup"])
    nodes                      = optional(list(string), [])
    namespace                  = optional(string)
    disable                    = optional(bool)
    generate_encryption_key    = optional(bool)
    backups = optional(object({
      keep_all              = optional(bool)
      keep_last             = optional(number)
      keep_hourly           = optional(number)
      keep_daily            = optional(number)
      keep_weekly           = optional(number)
      keep_monthly          = optional(number)
      keep_yearly           = optional(number)
      max_protected_backups = optional(number)
    }))
  }))
  default = {}
}
