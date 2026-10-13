###############################################################################
# Node network interfaces managed directly on the cluster (bpg/proxmox).
#
# Interfaces are staged by default (reload = false) and activated per node by
# proxmox_network_applier (network.tf) whenever any interface changes, so a
# batch of related changes takes effect together. Set reload = true on an
# interface to reload the node network immediately instead.
#
# Apply with `make pve-network` or the regular apply flow. All gated by
# var.manage_pve_resources.
###############################################################################

variable "network_bridges" {
  description = "Linux bridges, keyed by an arbitrary label. Fields: node_name, name (iface, e.g. 'vmbr1'), address (CIDR), gateway, ports (list of attached ifaces, e.g. ['eno1'] or ['bond0']), vlan_aware, vids ('2-4094'), mtu, autostart, comment, reload, timeout_reload."
  type = map(object({
    node_name  = string
    name       = string
    address    = optional(string)
    gateway    = optional(string)
    ports      = optional(list(string))
    vlan_aware = optional(bool)
    vids       = optional(string)
    mtu        = optional(number)
    autostart  = optional(bool, true)
    comment    = optional(string)
    reload     = optional(bool, false)
  }))
  default = {}
}

variable "network_bonds" {
  description = "Linux bonds, keyed by an arbitrary label. Fields: node_name, name (e.g. 'bond0'), slaves (required), bond_mode (balance-rr|active-backup|balance-xor|broadcast|802.3ad|balance-tlb|balance-alb), bond_primary (active-backup), bond_xmit_hash_policy (layer2|layer2+3|layer3+4), address, gateway, mtu, autostart, comment, reload."
  type = map(object({
    node_name             = string
    name                  = string
    slaves                = list(string)
    bond_mode             = optional(string)
    bond_primary          = optional(string)
    bond_xmit_hash_policy = optional(string)
    address               = optional(string)
    gateway               = optional(string)
    mtu                   = optional(number)
    autostart             = optional(bool, true)
    comment               = optional(string)
    reload                = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for b in var.network_bonds :
      b.bond_mode == null ? true : contains(
        ["balance-rr", "active-backup", "balance-xor", "broadcast", "802.3ad", "balance-tlb", "balance-alb"],
        b.bond_mode,
      )
    ])
    error_message = "network_bonds bond_mode must be one of balance-rr, active-backup, balance-xor, broadcast, 802.3ad, balance-tlb or balance-alb."
  }

  validation {
    condition = alltrue([
      for b in var.network_bonds :
      b.bond_xmit_hash_policy == null ? true : contains(["layer2", "layer2+3", "layer3+4"], b.bond_xmit_hash_policy)
    ])
    error_message = "network_bonds bond_xmit_hash_policy must be one of layer2, layer2+3 or layer3+4."
  }
}

variable "network_vlans" {
  description = "Linux VLAN interfaces, keyed by an arbitrary label. Fields: node_name, name ('eno1.99' shorthand, or a custom name with interface+vlan set), interface, vlan, address, gateway, mtu, autostart, comment, reload."
  type = map(object({
    node_name = string
    name      = string
    interface = optional(string)
    vlan      = optional(number)
    address   = optional(string)
    gateway   = optional(string)
    mtu       = optional(number)
    autostart = optional(bool, true)
    comment   = optional(string)
    reload    = optional(bool, false)
  }))
  default = {}
}
