###############################################################################
# Ceph configuration managed directly on the cluster (bpg/proxmox).
#
# The provider supports managing Ceph POOLS (proxmox_ceph_pool, experimental);
# deploying monitors/OSDs/managers (pveceph init) is not covered by the
# provider — bootstrap Ceph on a node manually first, then declare pools here.
#
# Apply with `make pve-ceph`. Gated by var.manage_pve_resources.
###############################################################################

variable "ceph_pools" {
  description = "Ceph pools, keyed by pool name. Fields: node_name (optional, node used to dispatch the API call; defaults to the bootstrap node), size, min_size, pg_num, pg_num_min, pg_autoscale_mode (on|off|warn), application (rbd|cephfs|rgw), crush_rule, erasure_coding ('k=4,m=2'), target_size, target_size_ratio, add_storages (also create the VM/CT storage entry)."
  type = map(object({
    node_name         = optional(string)
    size              = optional(number)
    min_size          = optional(number)
    pg_num            = optional(number)
    pg_num_min        = optional(number)
    pg_autoscale_mode = optional(string)
    application       = optional(string)
    crush_rule        = optional(string)
    erasure_coding    = optional(string)
    target_size       = optional(string)
    target_size_ratio = optional(number)
    add_storages      = optional(bool)
  }))
  default = {}

  validation {
    condition = alltrue([
      for p in var.ceph_pools :
      p.pg_autoscale_mode == null ? true : contains(["on", "off", "warn"], p.pg_autoscale_mode)
    ])
    error_message = "ceph_pools pg_autoscale_mode must be one of on, off or warn."
  }

  validation {
    condition = alltrue([
      for p in var.ceph_pools :
      p.application == null ? true : contains(["rbd", "cephfs", "rgw"], p.application)
    ])
    error_message = "ceph_pools application must be one of rbd, cephfs or rgw."
  }
}
