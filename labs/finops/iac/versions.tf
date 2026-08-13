# =============================================================================
# versions.tf — Versión de OpenTofu y providers
# -----------------------------------------------------------------------------
# No crea recursos: fija requisitos para `tofu init`.
#
# Lab 10-TP — FinOps:
#   Infra cloud real del lab = AWS Budget (techo USD 300 + alertas).
#   Estimación de costos (services.json / pricing.py) = LOCAL, no IaC.
#
#   create_budget=false (default) → solo valida JSON + escribe inventario
#                                   (Hobby / sin cuenta AWS).
#   create_budget=true            → aws_budgets_budget en AWS real / Learner Lab
#                                   (LocalStack Hobby = Pro-only → falla).
#
# Demos de estimación → python finops/finops_demo.py (se preserva).
# Alta bash alternativa → finops/create-budget.sh (se preserva).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
