# =============================================================================
# versions.tf — versión de OpenTofu + providers requeridos
# =============================================================================
# Workflow: tofu init → tofu plan → tofu apply
# `tofu init` descarga providers al directorio .terraform/ (no versionar).
# =============================================================================

terraform {
  # OpenTofu 1.6+ (compatible con HCL de Terraform)
  required_version = ">= 1.6"

  required_providers {
    # Tres aliases en providers.tf (localstack / ministack / minio)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Passwords master/etl/api en main.tf
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Zip de la Lambda (modules/lambda)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    # Inventarios JSON (vpc_config, ecs_inventory, finops, marcador EFS)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    # null_resource.rds_seed → local-exec post_rds.py
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
