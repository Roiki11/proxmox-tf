###############################################################################
# Node configuration managed through the PDM REST API
#
# PDM proxies a subset of node endpoints (/pve/remotes/{remote}/nodes/...).
# Writable through PDM: APT database updates (POST .../apt/update) and node
# firewall options (PUT .../firewall/options). Network interfaces,
# subscription and power management are read-only/proxied read-only in PDM
# 1.x — manage those directly on PVE (e.g. via the bpg/proxmox provider).
#
# Every entry here is applied on `make apply` (or per node with
# `make pdm-node-apply NODE=<name>`) after the cluster is registered as a
# remote (pdm_enabled = true).
###############################################################################

variable "pdm_node_config" {
  description = <<-EOT
    Map of node name -> configuration to apply through the PDM REST API.

      apt_update       : run POST /pve/remotes/{remote}/nodes/{node}/apt/update
                         (refresh the APT package database) when applied.
      firewall_options : body of PUT /pve/remotes/{remote}/nodes/{node}/firewall/options;
                         unset fields are omitted from the request:
                           enable                              bool
                           log_level_in / log_level_out / log_level_forward
                                              emerg|alert|crit|err|warning|notice|info|debug|nolog
                           log_nf_conntrack                    bool
                           ndp                                 bool
                           nosmurfs                            bool
                           nftables                            bool
                           protection_synflood                 bool
                           protection_synflood_rate            number
                           protection_synflood_burst           number
                           nf_conntrack_max                    number
                           nf_conntrack_tcp_timeout_established number
                           nf_conntrack_tcp_timeout_syn_recv   number
                           tcpflags                            bool
  EOT
  type = map(object({
    apt_update = optional(bool, false)
    firewall_options = optional(object({
      enable                               = optional(bool)
      log_level_in                         = optional(string)
      log_level_out                        = optional(string)
      log_level_forward                    = optional(string)
      log_nf_conntrack                     = optional(bool)
      ndp                                  = optional(bool)
      nosmurfs                             = optional(bool)
      nftables                             = optional(bool)
      protection_synflood                  = optional(bool)
      protection_synflood_rate             = optional(number)
      protection_synflood_burst            = optional(number)
      nf_conntrack_max                     = optional(number)
      nf_conntrack_tcp_timeout_established = optional(number)
      nf_conntrack_tcp_timeout_syn_recv    = optional(number)
      tcpflags                             = optional(bool)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.pdm_node_config) : contains(keys(var.nodes), name)
    ])
    error_message = format("pdm_node_config keys must be node names from var.nodes; invalid keys: %s", join(", ", [for n in keys(var.pdm_node_config) : n if !contains(keys(var.nodes), n)]))
  }
}
