# =============================================================================
# providers.tf — LocalStack (VPC lookup) + MiniStack (RDS/SM) + MinIO (S3)
# -----------------------------------------------------------------------------
# Tres backends locales del lab 08-TP (no mezclar endpoints):
#   LocalStack :4566 → solo data sources EC2 (VPC / subnets RDS / sg-rds)
#   MiniStack  :4567 → create-db-instance, subnet group, Secrets Manager DB
#   MinIO      :9000 → bucket snapshot-data-lake (opcional; decisión 002)
#
# Provider default = MiniStack (la mayoría de los resources viven ahí).
# Aliases: aws.localstack / aws.minio
#
# En AWS real: un solo provider, sin endpoints; VPC e instancia en la misma cuenta.
# =============================================================================

# ---------------------------------------------------------------------------
# Default — MiniStack (RDS + Secrets Manager de la DB)
# Credenciales dummy test/test (= compose / aws --endpoint-url :4567).
# ---------------------------------------------------------------------------
provider "aws" {
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
# Alias localstack — solo lookup de red del lab 07-v2 (NO crea VPC/SG)
# ---------------------------------------------------------------------------
provider "aws" {
  alias = "localstack"

  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = var.localstack_endpoint
    iam = var.localstack_endpoint
    sts = var.localstack_endpoint
    s3  = var.localstack_endpoint # evita hit a AWS real; no usamos S3 LS para el lake
  }
}

# ---------------------------------------------------------------------------
# Alias minio — bucket de snapshots (paso 9 del lab; dump lo hace Python)
# ---------------------------------------------------------------------------
provider "aws" {
  alias = "minio"

  region     = var.region
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
