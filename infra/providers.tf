# =============================================================================
# Providers AWS — tres backends locales (decisión 002)
# =============================================================================
#   aws.localstack (:4566) → IAM, EC2/VPC, Lambda, CloudWatch, STS, …
#   aws.ministack  (:4567) → RDS + Secrets Manager (capa DB)
#   aws.minio      (:9000) → object storage S3 (data lake)
#
# Cada module "…" elige uno con:
#   providers = { aws = aws.localstack | aws.ministack | aws.minio }
#
# En AWS real: un solo provider, sin bloque endpoints, credenciales reales.
# skip_* = true evita llamadas a APIs reales de validación de cuenta.
# =============================================================================

# ---------------------------------------------------------------------------
# LocalStack — cómputo / red / IAM / Lambda
# ---------------------------------------------------------------------------
provider "aws" {
  alias  = "localstack"
  region = var.region

  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Todas las APIs usadas por módulos “cloud” apuntan al mismo endpoint Hobby
  endpoints {
    apigateway           = var.localstack_endpoint
    cloudwatch           = var.localstack_endpoint
    cloudwatchevents     = var.localstack_endpoint
    cloudwatchlogs       = var.localstack_endpoint
    ec2                  = var.localstack_endpoint
    ecr                  = var.localstack_endpoint
    ecs                  = var.localstack_endpoint
    efs                  = var.localstack_endpoint
    elasticloadbalancing = var.localstack_endpoint
    iam                  = var.localstack_endpoint
    lambda               = var.localstack_endpoint
    s3                   = var.localstack_endpoint
    secretsmanager       = var.localstack_endpoint
    sns                  = var.localstack_endpoint
    sqs                  = var.localstack_endpoint
    ssm                  = var.localstack_endpoint
    sts                  = var.localstack_endpoint
  }
}

# ---------------------------------------------------------------------------
# MiniStack — RDS + Secrets de la DB (separado de LocalStack a propósito)
# ---------------------------------------------------------------------------
provider "aws" {
  alias  = "ministack"
  region = var.region

  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    rds            = var.ministack_endpoint
    secretsmanager = var.ministack_endpoint
    sts            = var.ministack_endpoint
  }
}

# ---------------------------------------------------------------------------
# MinIO — S3 del lake (credenciales minioadmin por defecto)
# s3_use_path_style: MinIO habla path-style (host/bucket), no virtual-host.
# ---------------------------------------------------------------------------
provider "aws" {
  alias  = "minio"
  region = var.region

  access_key = var.minio_access_key
  secret_key = var.minio_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = var.minio_endpoint
  }
}
