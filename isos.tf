# Phase 1: builds one automated-installation ISO per node by running
# proxmox-auto-install-assistant prepare-iso inside the assistant container.
#
# The ISO is rebuilt whenever the answer file, the first-boot hook, the base
# ISO checksum or the container image changes.

resource "terraform_data" "node_iso" {
  for_each = local.merged_nodes

  # The generated ISO path is stored in output so the destroy provisioner can
  # reference it via self (destroy provisioners may only reference self,
  # count.index and each.key).
  input = abspath(local.iso_paths[each.key])

  triggers_replace = [
    sha512(local.answer_contents[each.key]),
    var.cluster_bootstrap_enabled ? sha512(local.hook_contents[each.key]) : "no-first-boot-hook",
    (var.pve_iso_checksum != "" ? var.pve_iso_checksum : "no-checksum"),
    "${var.container_engine}:${var.container_platform}:${var.auto_install_assistant_image}",
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/build-iso.sh"

    environment = {
      CONTAINER_ENGINE   = var.container_engine
      CONTAINER_PLATFORM = var.container_platform
      CONTAINER_IMAGE    = var.auto_install_assistant_image
      BUILD_DIR          = abspath(local.build_dir)
      NODE               = each.key
      ANSWER_FILE        = abspath(local.answer_paths[each.key])
      HOOK_FILE          = try(abspath(local.hook_paths[each.key]), "")
      BASE_ISO           = abspath(local.base_iso_path)
      ISO_URL            = (var.pve_iso_url != null ? var.pve_iso_url : "")
      OUTPUT_FILE        = self.output
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f '${self.output}'"
  }

  # The generated files must be on disk before the container runs.
  depends_on = [
    local_file.answer,
    local_file.first_boot_hook,
  ]
}
