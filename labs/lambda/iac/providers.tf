# =============================================================================
# providers.tf — LocalStack (IAM + Lambda + Logs + EC2 lookup)
# -----------------------------------------------------------------------------
# Lab API endpoints (no mezclar):
#   LocalStack :4566 → IAM, Lambda, CloudWatch Logs, lookup VPC/sg-api
#   MiniStack  :4567 → secret dw/rds-api (prereq lab 08; no se crea acá)
#   MinIO      :9000 → export de logs (Python --skip-infra)
#   ALB stand-in :8088 → Compose (Python; Hobby no tiene ELBv2)
#
# En AWS real: un solo provider; ALB HTTPS real en public-alb-*.
# =============================================================================

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
    iam            = var.localstack_endpoint
    lambda         = var.localstack_endpoint
    logs           = var.localstack_endpoint
    sts            = var.localstack_endpoint
    s3             = var.localstack_endpoint
    secretsmanager = var.localstack_endpoint # evita hit AWS; secret DB = MiniStack
  }
}
