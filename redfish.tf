# Machine installation via the Dell Redfish provider (dell/dell_redfish).
#
# For every node with a bmc block (see variables.tf) whose PVE API does not
# answer yet ("not provisioned"), this flow:
#   1. attaches the node's auto-install ISO as virtual media,
#   2. arms a one-time boot override on the virtual CD,
#   3. resets / powers on the machine so the unattended installer runs.
#
# Requirements: `make isos` (ISOs built), `make iso-serve` (ISO served over
# HTTP from iso_http_base_url — the BMC fetches it), BMC passwords in the
# Vault KV secret (field bmc_<node>_password). Provisioning state is checked
# at plan time via data.external (scripts/node-provisioned-check.sh).
#
# Re-provisioning an installed node: run `terraform taint`/`tofu taint` on the
# node's resources or set node_install_force = true.

locals {
  # BMC connection info per node (password resolved from Vault below).
  redfish_nodes = {
    for name, node in var.nodes : name => {
      address        = node.bmc.address
      username       = node.bmc.username
      password_field = node.bmc.password_vault_field != null ? node.bmc.password_vault_field : "bmc_${name}_password"
      boot_target    = node.bmc.boot_target
      mgmt_ip        = element(split("/", node.management_cidr), 0)
      iso_url        = var.iso_http_base_url != "" ? "${var.iso_http_base_url}/${name}-auto.iso" : ""
    } if node.bmc != null
  }

  redfish_passwords = {
    for name, bmc in local.redfish_nodes : name => lookup(
      local.cluster_secrets,
      bmc.password_field,
      "",
    )
  }
}

# Provisioning state check, evaluated at plan time.
data "external" "node_provisioned" {
  for_each = var.node_install_enabled ? local.redfish_nodes : {}

  program = [
    "bash", "${path.module}/scripts/node-provisioned-check.sh",
  ]

  query = {
    node    = each.key
    mgmt_ip = each.value.mgmt_ip
  }
}

locals {
  # Nodes that still need installation.
  # Gated on node_install_enabled so the map is always empty (and never
  # touches the data.external instances) when the flow is disabled.
  nodes_to_install = var.node_install_enabled ? {
    for name, bmc in local.redfish_nodes : name => bmc
    if var.node_install_force ||
    try(data.external.node_provisioned[name].result.provisioned, "true") == "false"
  } : {}
}

resource "redfish_virtual_media" "install" {
  for_each = var.node_install_enabled ? local.nodes_to_install : {}

  image = each.value.iso_url

  redfish_server {
    endpoint     = each.value.address
    user         = each.value.username
    password     = local.redfish_passwords[each.key]
    ssl_insecure = var.redfish_ssl_insecure
  }

  lifecycle {
    precondition {
      condition     = each.value.iso_url != ""
      error_message = format("iso_http_base_url must be set (the BMC fetches '%s' over HTTP) for node '%s'", "${var.iso_http_base_url}/${each.key}-auto.iso", each.key)
    }

    precondition {
      condition     = local.redfish_passwords[each.key] != ""
      error_message = format("The Vault secret field '%s' must contain the BMC password for node '%s'", each.value.password_field, each.key)
    }

    precondition {
      condition     = !var.node_install_force || var.node_install_enabled
      error_message = "node_install_force requires node_install_enabled = true"
    }
  }
}

resource "redfish_boot_source_override" "install" {
  for_each = var.node_install_enabled ? local.nodes_to_install : {}

  reset_type                   = var.node_install_reset_type
  reset_timeout                = var.node_install_reset_timeout
  boot_source_job_timeout      = var.node_install_boot_job_timeout
  boot_source_override_enabled = "Once"
  boot_source_override_target  = each.value.boot_target

  redfish_server {
    endpoint     = each.value.address
    user         = each.value.username
    password     = local.redfish_passwords[each.key]
    ssl_insecure = var.redfish_ssl_insecure
  }

  depends_on = [redfish_virtual_media.install]
}

resource "redfish_power" "install" {
  for_each = var.node_install_enabled && var.node_install_power_on ? local.nodes_to_install : {}

  desired_power_action = "ForceOn"
  maximum_wait_time    = var.node_install_power_wait
  check_interval       = 10

  redfish_server {
    endpoint     = each.value.address
    user         = each.value.username
    password     = local.redfish_passwords[each.key]
    ssl_insecure = var.redfish_ssl_insecure
  }

  depends_on = [redfish_boot_source_override.install]
}
