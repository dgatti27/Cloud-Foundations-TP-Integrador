# =============================================================================
# versions.tf — Versión de OpenTofu y del provider AWS
# -----------------------------------------------------------------------------
# No crea recursos: fija requisitos para `tofu init`.
#
# Lab 04: identidad (IAM/STS) en LocalStack (:4566)
#         + buckets de referencia *-data-raw en MinIO (:9000) — decisión 002.
#
# Infra (grupos, policies, users, roles, buckets) → este directorio.
# Demos (access key larga, AssumeRole, list MinIO)
#   → python iam/iam_demo.py --skip-infra
#
# El módulo iac/tp/modules/iam es el IAM del TP completo (más roles).
# Este stack es autocontenido para lab-04.
# =============================================================================

terraform {
  # Versión mínima de OpenTofu/Terraform CLI que entiende esta config
  required_version = ">= 1.6.0"

  required_providers {
    # Mismo plugin "aws" para LocalStack (IAM) y MinIO (S3) vía endpoints/alias
    aws = {
      source  = "hashicorp/aws" # registro oficial del plugin
      version = "~> 5.0"        # 5.x compatible; no salta a 6.x sin querer
    }
  }
}
