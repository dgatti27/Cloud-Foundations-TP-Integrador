# =============================================================================
# versions.tf — Versión de OpenTofu y del provider AWS
# -----------------------------------------------------------------------------
# Define con qué "motores" se interpreta este stack.
# No crea recursos: solo fija requisitos para `tofu init`.
#
# Lab 06: data lake en MinIO (API S3).
# Infra (buckets/versioning/SSE/policies) → este directorio.
# Demos (mutate, AssumeRole, presign)     → python s3/s3_demo.py --skip-infra
# =============================================================================

terraform {
  # Versión mínima de OpenTofu/Terraform CLI que entiende esta config
  required_version = ">= 1.6.0"

  required_providers {
    # Provider "aws" habla API S3 (también contra MinIO vía endpoints en providers.tf)
    aws = {
      source  = "hashicorp/aws" # registro oficial del plugin
      version = "~> 5.0"        # 5.x compatible; no salta a 6.x sin querer
    }
  }
}
