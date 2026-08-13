# =============================================================================
# providers.tf — Cómo OpenTofu habla con LocalStack
# -----------------------------------------------------------------------------
# Un provider aws apuntando a LocalStack (:4566) para EC2/VPC/IAM/STS.
# El data lake S3 NO es este endpoint: MinIO (:9000) — decisión 002 / lab 06.
#
# En AWS real: mismo main.tf, sin bloque `endpoints { }`, credenciales de cuenta.
# =============================================================================

provider "aws" {
  region = var.region # define AZs: us-east-1a / us-east-1b

  # Credenciales dummy de LocalStack (compose / awslocal usan test/test)
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  # Flags típicos de emuladores (no hay IMDS ni cuenta real)
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = var.localstack_endpoint # VPC, subnets, IGW, NAT, SGs, routes, vpce
    iam = var.localstack_endpoint # por si algún recurso resuelve IAM
    sts = var.localstack_endpoint
    # s3 LocalStack: NO usar para el lake; solo evita que el provider busque AWS real
    s3  = var.localstack_endpoint
  }
}
