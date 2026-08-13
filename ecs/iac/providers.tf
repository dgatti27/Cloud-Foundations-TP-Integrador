# =============================================================================
# providers.tf — LocalStack (IAM/VPC/ECS/EFS) + MiniStack (Secrets origen)
# -----------------------------------------------------------------------------
# Lab 09b endpoints (no mezclar):
#   LocalStack :4566 → IAM roles + lookup sg-efs/subnets (+ ECS/EFS si enable_ecs_api)
#   MiniStack  :4567 → secret dw/origen-demo (camino A)
#   Compose    :8080 → Airflow runtime (NO es OpenTofu — ecs_demo.py)
#
# Provider default = LocalStack (la mayoría de los resources).
# Alias aws.ministack = Secrets del origen demo.
#
# En AWS real: un solo provider; Fargate + EFS reales (enable_ecs_api=true).
# =============================================================================

# ---------------------------------------------------------------------------
# Default — LocalStack
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.region

  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2            = var.localstack_endpoint
    ecr            = var.localstack_endpoint
    ecs            = var.localstack_endpoint
    efs            = var.localstack_endpoint
    iam            = var.localstack_endpoint
    sts            = var.localstack_endpoint
    s3             = var.localstack_endpoint
    secretsmanager = var.localstack_endpoint # no usado acá para DB; evita hit AWS
  }
}

# ---------------------------------------------------------------------------
# Alias ministack — secret dw/origen-demo (camino A)
# dw/rds-etl lo crea el lab 08-tp; no lo recreamos.
# ---------------------------------------------------------------------------
provider "aws" {
  alias = "ministack"

  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    secretsmanager = var.ministack_endpoint
    sts            = var.ministack_endpoint
  }
}
