# =============================================================================
# versions.tf — Versión de OpenTofu y providers
# -----------------------------------------------------------------------------
# No crea recursos: fija requisitos para `tofu init`.
#
# Lab API-TP: Lambda GET gold (tp-gold-api) en LocalStack.
#   - IAM: api-role + bi-api (+ InlineInvoke en bi-ops)
#   - Zip handler+query_gold+pg8000 → aws_lambda_function
#   - Log group /aws/lambda/tp-gold-api
#
# Runtime Hobby (ALB stand-in, invoke, export logs→MinIO)
#   → python lambda/lambda_demo.py --skip-infra
#
# El módulo infra/modules/lambda es la misma idea a escala TP (lab 09).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Empaquetado zip (handler + query_gold); pg8000 lo agrega scripts/build_lambda_zip.py
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    # local-exec del build con pg8000 (pip install --target)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
