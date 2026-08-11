locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "OpenTofu"
    Lab       = "09-tp"
  }

  repo_root_abs = abspath("${path.root}/${var.repo_root}")
}
