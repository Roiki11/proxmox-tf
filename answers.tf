# Phase 1: renders the per-node answer.toml and first-boot hooks used by the
# automated installer (embedded into each node's ISO by scripts/build-iso.sh).

resource "local_file" "answer" {
  for_each = local.merged_nodes

  content  = local.answer_contents[each.key]
  filename = local.answer_paths[each.key]

  # Contains the root password: keep it private.
  file_permission      = "0600"
  directory_permission = "0700"

  lifecycle {
    precondition {
      condition     = contains(keys(var.nodes), local.bootstrap_node)
      error_message = format("bootstrap_node '%s' is not a key of var.nodes (keys: %s)", local.bootstrap_node, join(", ", sort(keys(var.nodes))))
    }

    precondition {
      condition = var.cluster_bootstrap_enabled ? (
        lookup(local.cluster_secrets, "root_password", "") != ""
        ) : (
        lookup(local.cluster_secrets, "root_password", "") != "" || lookup(local.cluster_secrets, "root_password_hashed", "") != ""
      )
      error_message = "When cluster_bootstrap_enabled is true, the Vault secret must contain a 'root_password' field (the join hooks authenticate with it). Otherwise, it must contain at least one of 'root_password' or 'root_password_hashed'."
    }
  }
}

resource "local_file" "first_boot_hook" {
  for_each = local.hook_contents

  content  = local.hook_contents[each.key]
  filename = local.hook_paths[each.key]

  file_permission      = "0700"
  directory_permission = "0700"
}
