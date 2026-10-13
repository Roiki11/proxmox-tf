# SDN configuration (bpg/proxmox): zones by type, VNets, subnets, applier.
# Declared in variables-sdn.tf; applied with `make pve-sdn`.

resource "proxmox_sdn_zone_simple" "zones" {
  for_each = var.manage_pve_resources ? { for id, z in var.sdn_zones : id => z if z.type == "simple" } : {}

  id    = each.key
  nodes = each.value.nodes
  mtu   = each.value.mtu

  dns         = each.value.dns
  dns_zone    = each.value.dns_zone
  ipam        = each.value.ipam
  reverse_dns = each.value.reverse_dns
  dhcp        = each.value.dhcp
}

resource "proxmox_sdn_zone_vlan" "zones" {
  for_each = var.manage_pve_resources ? { for id, z in var.sdn_zones : id => z if z.type == "vlan" } : {}

  id = each.key
  # Required for vlan zones; enforced by the precondition below.
  bridge = coalesce(each.value.bridge, "vmbr0")
  nodes  = each.value.nodes
  mtu    = each.value.mtu

  dns         = each.value.dns
  dns_zone    = each.value.dns_zone
  ipam        = each.value.ipam
  reverse_dns = each.value.reverse_dns

  lifecycle {
    precondition {
      condition     = each.value.bridge != null
      error_message = format("SDN vlan zone '%s' requires the 'bridge' field", each.key)
    }
  }
}

resource "proxmox_sdn_zone_vxlan" "zones" {
  for_each = var.manage_pve_resources ? { for id, z in var.sdn_zones : id => z if z.type == "vxlan" } : {}

  id    = each.key
  peers = each.value.peers
  nodes = each.value.nodes
  mtu   = each.value.mtu

  dns         = each.value.dns
  dns_zone    = each.value.dns_zone
  ipam        = each.value.ipam
  reverse_dns = each.value.reverse_dns

  lifecycle {
    precondition {
      condition     = each.value.peers != null && length(each.value.peers) > 0
      error_message = format("SDN vxlan zone '%s' requires the 'peers' field (list of node IPs)", each.key)
    }
  }
}

resource "proxmox_sdn_zone_evpn" "zones" {
  for_each = var.manage_pve_resources ? { for id, z in var.sdn_zones : id => z if z.type == "evpn" } : {}

  id         = each.key
  controller = coalesce(each.value.controller, "")
  vrf_vxlan  = coalesce(each.value.vrf_vxlan, 0)
  nodes      = each.value.nodes
  mtu        = each.value.mtu

  advertise_subnets          = each.value.advertise_subnets
  disable_arp_nd_suppression = each.value.disable_arp_nd_suppression
  exit_nodes                 = each.value.exit_nodes
  exit_nodes_local_routing   = each.value.exit_nodes_local_routing
  primary_exit_node          = each.value.primary_exit_node
  rt_import                  = each.value.rt_import

  dns         = each.value.dns
  dns_zone    = each.value.dns_zone
  ipam        = each.value.ipam
  reverse_dns = each.value.reverse_dns

  lifecycle {
    precondition {
      condition     = each.value.controller != null && each.value.vrf_vxlan != null
      error_message = format("SDN evpn zone '%s' requires the 'controller' and 'vrf_vxlan' fields", each.key)
    }
  }
}

resource "proxmox_sdn_vnet" "vnets" {
  for_each = var.manage_pve_resources ? var.sdn_vnets : {}

  id   = each.key
  zone = each.value.zone

  tag           = each.value.tag
  alias         = each.value.alias
  isolate_ports = each.value.isolate_ports
  vlan_aware    = each.value.vlan_aware

  depends_on = [
    proxmox_sdn_zone_simple.zones,
    proxmox_sdn_zone_vlan.zones,
    proxmox_sdn_zone_vxlan.zones,
    proxmox_sdn_zone_evpn.zones,
  ]

  lifecycle {
    precondition {
      condition     = contains(keys(var.sdn_zones), each.value.zone)
      error_message = format("SDN vnet '%s' references unknown zone '%s'", each.key, each.value.zone)
    }
  }
}

# DHCP ranges are not declarable (see variables-sdn.tf note) — the provider
# cannot handle unknown values for the dhcp_range object attribute.

resource "proxmox_sdn_subnet" "subnets" {
  for_each = var.manage_pve_resources ? var.sdn_subnets : {}

  cidr = each.value.cidr
  vnet = each.value.vnet

  gateway         = each.value.gateway
  snat            = each.value.snat
  dhcp_dns_server = each.value.dhcp_dns_server
  dns_zone_prefix = each.value.dns_zone_prefix

  depends_on = [proxmox_sdn_vnet.vnets]

  lifecycle {
    precondition {
      condition     = contains(keys(var.sdn_vnets), each.value.vnet)
      error_message = format("SDN subnet '%s' references unknown vnet '%s'", each.key, each.value.vnet)
    }
  }
}

resource "proxmox_sdn_applier" "apply" {
  count = var.manage_pve_resources && var.sdn_apply ? 1 : 0

  # Activates everything staged in this apply round.
  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_simple.zones,
      proxmox_sdn_zone_vlan.zones,
      proxmox_sdn_zone_vxlan.zones,
      proxmox_sdn_zone_evpn.zones,
      proxmox_sdn_vnet.vnets,
      proxmox_sdn_subnet.subnets,
    ]
  }

  depends_on = [
    proxmox_sdn_zone_simple.zones,
    proxmox_sdn_zone_vlan.zones,
    proxmox_sdn_zone_vxlan.zones,
    proxmox_sdn_zone_evpn.zones,
    proxmox_sdn_vnet.vnets,
    proxmox_sdn_subnet.subnets,
  ]
}
