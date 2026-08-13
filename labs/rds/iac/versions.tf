# =============================================================================
# versions.tf — Versión de OpenTofu y providers
# -----------------------------------------------------------------------------
# No crea recursos: fija requisitos para `tofu init`.
#
# Lab 08-TP: RDS PostgreSQL Multi-AZ (tp-dw-db) en MiniStack (:4567)
#            + secrets DB + lookup de red en LocalStack (:4566)
#            + bucket snapshot opcional en MinIO (:9000)
#
# Infra (subnet group, instancia, secrets, seed opcional) → este directorio.
# Demos (verify privilegios, snapshot API + pg_dump→MinIO)
#   → python rds/rds_tp_demo.py --skip-infra
#
# El módulo infra/modules/rds (+ secrets + null_resource) es la misma idea
# a escala TP (lab 09). Este stack es autocontenido para lab-08-tp.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # RDS/Secrets → MiniStack; EC2 lookup → LocalStack; S3 bucket → MinIO
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Passwords master / etl_writer / api_reader (no van en claro en el repo)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # null_resource + local-exec para seed_tp.sql (docker exec)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
