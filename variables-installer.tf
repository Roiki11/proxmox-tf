###############################################################################
# Installer answer file values (see https://pve.proxmox.com/wiki/Automated_Installation)
###############################################################################

variable "root_ssh_keys" {
  description = "SSH public keys added to root's authorized_keys on every installed node."
  type        = list(string)
  default     = []
}

variable "keyboard" {
  description = "Keyboard layout for the installer and default console layout (e.g. 'en-us', 'de', 'fi')."
  type        = string
  default     = "en-us"
}

variable "country" {
  description = "Two-letter country code used to select a nearby package mirror."
  type        = string
  default     = "us"
}

variable "mailto" {
  description = "Default mail address for the root user on installed nodes."
  type        = string
  default     = null
}

variable "reboot_on_error" {
  description = "Reboot automatically when the installer hits an error instead of dropping to a shell."
  type        = bool
  default     = false
}

variable "post_installation_webhook" {
  description = "Optional webhook the installer POSTs system information to after a successful installation. Its bearer token comes from the Vault field post_installation_webhook_token."
  type = object({
    url              = string
    cert_fingerprint = optional(string)
  })
  default = null
}

###############################################################################
# ISO generation (proxmox-auto-install-assistant in a container)
###############################################################################

variable "container_engine" {
  description = "OCI container engine binary used to run the auto-install assistant (docker or podman)."
  type        = string
  default     = "docker"
}

variable "container_platform" {
  description = "Optional --platform flag (e.g. 'linux/amd64' when building ISOs on Apple Silicon)."
  type        = string
  default     = ""
}

variable "auto_install_assistant_image" {
  description = "Container image of the proxmox-auto-install-assistant wrapper (e.g. built from proxmox_auto_install_assistant_container). Must contain the assistant and xorriso binaries and accept a /work mount."
  type        = string
  default     = "proxmox-auto-install-assistant:latest"
}

variable "pve_iso_url" {
  description = "URL of the Proxmox VE ISO downloaded automatically when the base ISO is missing."
  type        = string
  default     = null
}

variable "pve_iso_path" {
  description = "Path of the base PVE ISO to prepare. Defaults to '<build_dir>/base/proxmox-ve.iso'."
  type        = string
  default     = null
}

variable "pve_iso_checksum" {
  description = "Known checksum of the base ISO; ISOs are rebuilt automatically whenever it changes."
  type        = string
  default     = ""
}

variable "build_dir" {
  description = "Directory where answer files, hooks and prepared ISOs are generated."
  type        = string
  default     = "./build"
}
