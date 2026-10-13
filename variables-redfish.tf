###############################################################################
# Machine installation via the Dell Redfish provider (dell/dell_redfish).
#
# For nodes with a declared bmc block (var.nodes.<name>.bmc), the install
# flow (redfish.tf) attaches the node's auto-install ISO as virtual media,
# sets a one-time boot override and resets/powers the machine — but only for
# nodes whose PVE API does not answer yet (provisioned check).
#
# Secrets: BMC passwords come from the Vault KV secret (field
# bmc_<node>_password, override with nodes.<name>.bmc.password_vault_field).
###############################################################################

variable "node_install_enabled" {
  description = "Enable the Redfish-based machine installation flow for BMC-declared nodes (redfish.tf)."
  type        = bool
  default     = false
}

variable "node_install_force" {
  description = "Re-run the installation flow even when the node's PVE API is already answering (dangerous: re-installs the node)."
  type        = bool
  default     = false
}

variable "redfish_ssl_insecure" {
  description = "Skip TLS verification of the BMC endpoints (self-signed certificates)."
  type        = bool
  default     = true
}

variable "node_install_reset_type" {
  description = "Reset applied after the one-time boot override is armed (the machine then boots from the virtual CD). For machines that are powered off, 'PowerCycle' powers them on."
  type        = string
  default     = "ForceRestart"

  validation {
    condition     = contains(["ForceRestart", "GracefulRestart", "PowerCycle"], var.node_install_reset_type)
    error_message = "node_install_reset_type must be one of ForceRestart, GracefulRestart or PowerCycle."
  }
}

variable "node_install_reset_timeout" {
  description = "Seconds the provider waits for the machine to reset before timing out."
  type        = number
  default     = 600
}

variable "node_install_boot_job_timeout" {
  description = "Seconds the provider waits for the boot-source-override job to complete before timing out."
  type        = number
  default     = 1200
}

variable "node_install_power_on" {
  description = "Additionally issue a redfish_power ForceOn after arming the boot override — belt and braces for machines that are powered off."
  type        = bool
  default     = true
}

variable "node_install_power_wait" {
  description = "Seconds the power resource waits for the machine to reach the desired power state."
  type        = number
  default     = 300
}
