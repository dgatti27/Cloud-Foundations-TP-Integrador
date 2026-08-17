# =============================================================================
# locals.tf — valores derivados reutilizados en el root
# =============================================================================

locals {
  # Tags comunes en casi todos los recursos (Project + ManagedBy)
  common_tags = {
    Project   = var.project_name
    ManagedBy = "OpenTofu"
  }

  # Ruta absoluta a la raíz del repo (seed SQL, apps/api, apps/airflow, labs/)
  # var.repo_root default ".." relativo a infra/
  repo_root_abs = abspath("${path.root}/${var.repo_root}")
}
