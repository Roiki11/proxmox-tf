# Ceph pools (bpg/proxmox, experimental resource).
# Declared in variables-ceph.tf; applied with `make pve-ceph`.

resource "proxmox_ceph_pool" "pools" {
  for_each = var.manage_pve_resources ? var.ceph_pools : {}

  # The pool is cluster-wide; the node only dispatches the API call.
  node_name = each.value.node_name != null ? each.value.node_name : local.bootstrap_node
  name      = each.key

  size              = each.value.size
  min_size          = each.value.min_size
  pg_num            = each.value.pg_num
  pg_num_min        = each.value.pg_num_min
  pg_autoscale_mode = each.value.pg_autoscale_mode
  application       = each.value.application
  crush_rule        = each.value.crush_rule
  erasure_coding    = each.value.erasure_coding
  target_size       = each.value.target_size
  target_size_ratio = each.value.target_size_ratio
  add_storages      = each.value.add_storages

  lifecycle {
    precondition {
      condition     = contains(keys(var.nodes), each.value.node_name != null ? each.value.node_name : local.bootstrap_node)
      error_message = format("ceph_pools node_name '%s' is not a node of var.nodes", each.value.node_name != null ? each.value.node_name : local.bootstrap_node)
    }
  }
}
