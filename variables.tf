###############################################################################
# Cluster topology
###############################################################################

variable "cluster_name" {
  description = "Name of the Proxmox VE cluster. Max 15 characters (PVE 'pve-node' format)."
  type        = string

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 15
    error_message = "cluster_name must be between 1 and 15 characters long."
  }
}

variable "cluster_domain" {
  description = "DNS search domain used for node FQDNs (e.g. 'example.lan')."
  type        = string
  default     = "lan"
}

variable "nodes" {
  description = <<-EOT
    Map of Proxmox VE nodes to install with auto-install ISOs. The key becomes the
    node hostname and must match PVE node naming rules (lowercase, no dots).

    Per-node fields:
      management_cidr : management IP in CIDR notation (e.g. '10.0.0.11/24'). Required.
      gateway         : default gateway. Falls back to node_defaults.
      dns_server      : DNS server used by the installer and the node. Falls back to node_defaults.
      dhcp            : set true to let the installer use DHCP for this node. Defaults to node_defaults (false).
      nic_filter      : map of udev properties to select the management NIC (e.g. {"ID_NET_NAME" = "eno1"}).
      disks           : list of disks for [disk-setup] disk-list (e.g. ["sda", "sdb"]).
                        Ignored when disk_filter is set (the installer forbids defining both).
      disk_filter     : map of udev properties to select disks instead of disk-list (e.g. {"ID_SERIAL" = "KIOXIA*"}).
      filter_match    : 'any' or 'all'. Defaults to node_defaults ('any').
      filesystem      : 'ext4', 'xfs', 'zfs' or 'btrfs'. Defaults to node_defaults ('ext4').
      zfs_raid        : zfs raid level when filesystem=zfs ('raid0','raid1','raid10','raidz-1','raidz-2','raidz-3').
      zfs_ashift      : zfs ashift value (usually 12).
      zfs_arc_max     : zfs ARC maximum in MiB.
      lvm_hdsize      : hdsize in GiB for ext4/xfs (reserves space at the end of the disk).
      lvm_swapsize    : swap size in GiB for ext4/xfs.
      timezone        : tzdata timezone. Falls back to node_defaults.
  EOT
  type = map(object({
    management_cidr = string
    gateway         = optional(string)
    dns_server      = optional(string)
    dhcp            = optional(bool)
    nic_filter      = optional(map(string))
    disks           = optional(list(string))
    disk_filter     = optional(map(string))
    filter_match    = optional(string)
    filesystem      = optional(string)
    zfs_raid        = optional(string)
    zfs_ashift      = optional(number)
    zfs_arc_max     = optional(number)
    lvm_hdsize      = optional(number)
    lvm_swapsize    = optional(number)
    timezone        = optional(string)
    bmc = optional(object({
      address              = string
      username             = optional(string, "root")
      password_vault_field = optional(string)
      boot_target          = optional(string, "Cd")
    }))
  }))

  validation {
    condition = alltrue([
      for n in var.nodes :
      contains(["ext4", "xfs", "zfs", "btrfs"], n.filesystem == null ? "ext4" : n.filesystem)
    ])
    error_message = "filesystem must be one of ext4, xfs, zfs or btrfs."
  }

  validation {
    condition = alltrue([
      for n in var.nodes :
      n.zfs_raid == null ? true : contains(["raid0", "raid1", "raid10", "raidz-1", "raidz-2", "raidz-3"], n.zfs_raid)
    ])
    error_message = "zfs_raid must be one of raid0, raid1, raid10, raidz-1, raidz-2 or raidz-3."
  }
}

variable "node_defaults" {
  description = "Defaults applied to every node in var.nodes (per-node values win)."
  type = object({
    gateway      = optional(string)
    dns_server   = optional(string)
    dhcp         = optional(bool, false)
    nic_filter   = optional(map(string))
    disks        = optional(list(string))
    disk_filter  = optional(map(string))
    filter_match = optional(string, "any")
    filesystem   = optional(string, "ext4")
    zfs_raid     = optional(string)
    zfs_ashift   = optional(number)
    zfs_arc_max  = optional(number)
    lvm_hdsize   = optional(number)
    lvm_swapsize = optional(number)
    timezone     = optional(string, "UTC")
  })
  default = {}
}

variable "bootstrap_node" {
  description = "Key of the node in var.nodes that creates the cluster. Defaults to the alphabetically first node."
  type        = string
  default     = ""
}

variable "cluster_bootstrap_enabled" {
  description = "Embed a first-boot hook in each ISO so nodes automatically create/join the cluster. Disable to install standalone nodes and manage clustering yourself."
  type        = bool
  default     = true
}
