###############################################################################
# SDN configuration managed directly on the cluster (bpg/proxmox).
#
# Zones are declared in one map and dispatched to the matching zone resource
# by their 'type' (simple | vlan | vxlan | evpn). VNets attach to zones and
# subnets to VNets. Changes are staged by Proxmox and activated by the
# proxmox_sdn_applier when var.sdn_apply = true.
#
# Apply with `make pve-sdn` or the regular apply flow. All gated by
# var.manage_pve_resources.
###############################################################################

variable "sdn_zones" {
  description = <<-EOT
    SDN zones, keyed by zone ID. Common fields: type (simple|vlan|vxlan|evpn),
    nodes (list, empty = all nodes), mtu, dns, dns_zone, ipam, reverse_dns, dhcp (dnsmasq).

    Type-specific fields:
      vlan  : bridge (required)
      vxlan : peers (required, list of node IPs of the VXLAN underlay)
      evpn  : controller (required), vrf_vxlan (required), advertise_subnets,
              disable_arp_nd_suppression, exit_nodes, exit_nodes_local_routing,
              primary_exit_node, rt_import
  EOT
  type = map(object({
    type        = string
    nodes       = optional(list(string), [])
    mtu         = optional(number)
    dns         = optional(string)
    dns_zone    = optional(string)
    ipam        = optional(string)
    reverse_dns = optional(string)
    dhcp        = optional(string)
    # vlan
    bridge = optional(string)
    # vxlan
    peers = optional(list(string))
    # evpn
    controller                 = optional(string)
    vrf_vxlan                  = optional(number)
    advertise_subnets          = optional(bool)
    disable_arp_nd_suppression = optional(bool)
    exit_nodes                 = optional(list(string))
    exit_nodes_local_routing   = optional(bool)
    primary_exit_node          = optional(string)
    rt_import                  = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for z in var.sdn_zones : contains(["simple", "vlan", "vxlan", "evpn"], z.type)
    ])
    error_message = "sdn_zones type must be one of simple, vlan, vxlan or evpn."
  }
}

variable "sdn_vnets" {
  description = "SDN VNets, keyed by VNet ID. Fields: zone (required, a key of sdn_zones), tag (VLAN/VXLAN tag), alias, isolate_ports, vlan_aware."
  type = map(object({
    zone          = string
    tag           = optional(number)
    alias         = optional(string)
    isolate_ports = optional(bool)
    vlan_aware    = optional(bool)
  }))
  default = {}
}

# NOTE: the provider's dhcp_range object attribute cannot handle unknown
# values at plan/validate time (bpg/proxmox bug), so DHCP ranges are not
# declarable here. Configure them via the PVE UI/API or PDM afterwards.
variable "sdn_subnets" {
  description = "SDN subnets, keyed by an arbitrary label. Fields: vnet (required, a key of sdn_vnets), cidr (required), gateway, snat, dhcp_dns_server, dns_zone_prefix. (DHCP ranges are not declarable — see note above.)"
  type = map(object({
    vnet            = string
    cidr            = string
    gateway         = optional(string)
    snat            = optional(bool)
    dhcp_dns_server = optional(string)
    dns_zone_prefix = optional(string)
  }))
  default = {}
}

variable "sdn_apply" {
  description = "Create the SDN applier that activates staged zone/vnet/subnet changes (PUT /cluster/sdn)."
  type        = bool
  default     = true
}
