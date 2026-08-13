locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "OpenTofu"
  }

  repo_root_abs = abspath("${path.root}/${var.repo_root}")
}
