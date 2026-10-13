# Node network interfaces + per-node reload applier (bpg/proxmox).
# Declared in variables-network.tf; applied with `make pve-network`.

resource "proxmox_network_linux_vlan" "vlans" {
  for_each = var.manage_pve_resources ? var.network_vlans : {}

  node_name = each.value.node_name
  name      = each.value.name

  interface = each.value.interface
  vlan      = each.value.vlan
  address   = each.value.address
  gateway   = each.value.gateway
  mtu       = each.value.mtu
  autostart = each.value.autostart
  comment   = each.value.comment
  reload    = each.value.reload
}

resource "proxmox_network_linux_bond" "bonds" {
  for_each = var.manage_pve_resources ? var.network_bonds : {}

  node_name = each.value.node_name
  name      = each.value.name
  slaves    = each.value.slaves

  bond_mode             = each.value.bond_mode
  bond_primary          = each.value.bond_primary
  bond_xmit_hash_policy = each.value.bond_xmit_hash_policy
  address               = each.value.address
  gateway               = each.value.gateway
  mtu                   = each.value.mtu
  autostart             = each.value.autostart
  comment               = each.value.comment
  reload                = each.value.reload
}

resource "proxmox_network_linux_bridge" "bridges" {
  for_each = var.manage_pve_resources ? var.network_bridges : {}

  node_name = each.value.node_name
  name      = each.value.name

  address    = each.value.address
  gateway    = each.value.gateway
  ports      = each.value.ports
  vlan_aware = each.value.vlan_aware
  vids       = each.value.vids
  mtu        = each.value.mtu
  autostart  = each.value.autostart
  comment    = each.value.comment
  reload     = each.value.reload

  # VLAN interfaces must exist before they can be attached as ports.
  depends_on = [proxmox_network_linux_vlan.vlans, proxmox_network_linux_bond.bonds]
}

locals {
  # Nodes that own at least one managed interface get a network applier that
  # activates all staged changes (reload = false) in one reload.
  network_applier_nodes = var.manage_pve_resources ? distinct(concat(
    [for _, b in var.network_bridges : b.node_name],
    [for _, b in var.network_bonds : b.node_name],
    [for _, v in var.network_vlans : v.node_name],
  )) : []

}

resource "proxmox_network_applier" "nodes" {
  for_each = toset(local.network_applier_nodes)

  node_name = each.key

  # Reload also on destroy so staged deletions take effect.
  on_create  = true
  on_destroy = true

  # Reload whenever any managed interface on the cluster changes. The reload
  # applies everything staged on this node; interfaces with reload = true
  # reload themselves and are harmless here.
  lifecycle {
    replace_triggered_by = [
      proxmox_network_linux_bridge.bridges,
      proxmox_network_linux_bond.bonds,
      proxmox_network_linux_vlan.vlans,
    ]
  }

  depends_on = [
    proxmox_network_linux_bridge.bridges,
    proxmox_network_linux_bond.bonds,
    proxmox_network_linux_vlan.vlans,
  ]
}
