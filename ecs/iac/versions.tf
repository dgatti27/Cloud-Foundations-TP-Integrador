# =============================================================================
# versions.tf — Versión de OpenTofu y providers
# -----------------------------------------------------------------------------
# No crea recursos: fija requisitos para `tofu init`.
#
# Lab 09b-TP: cómputo ETL (stand-in Fargate + EFS + Airflow) en Hobby.
#   - IAM modelo (ecsTaskExecutionRole + InlineEtlSecrets en app-role) → LocalStack
#   - Secret dw/origen-demo → MiniStack (opcional)
#   - Marcadores efs-standin/ + inventario JSON (sin API EFS en Community)
#   - Opcional enable_ecs_api=true → cluster ECS + EFS API (Pro / AWS real)
#
# Runtime (Compose, trigger DAG, verify, ERP) → python ecs/ecs_demo.py --skip-infra
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Escribe .iac-managed + efs_inventory.json en el repo
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
