# Define la infra como codigo (Terraform / OpenTofu) apuntando a MinIO
# como object storage local (API compatible con S3). Ver docs/decisions.md #002.
# Al hacer `tofu apply` (o `terraform apply`) crea los 3 buckets del data lake en MinIO.

# Setup: Terraform/OpenTofu >= 1.5 y provider AWS ~> 5.0.
# El provider minio (aminueza/minio) se agregara cuando se gestionen
# politicas, grupos y usuarios nativos de MinIO.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Descomentar cuando se gestionen users/groups/policies de MinIO:
    # minio = {
    #   source  = "aminueza/minio"
    #   version = "~> 2.0"
    # }
  }
}

locals {
  project_name  = "TP-Integrador"
  # Prefijo en minusculas: MinIO/S3 exige nombres de bucket DNS-compatibles. Es lo mismo para localstack
  bucket_prefix = "tp-integrador"
  environment   = var.environment
}

# -----------------------------------------------------------------------------
# Alternativa Minio
# Provider activo: AWS API -> MinIO (data lake local).
# Credenciales = MINIO_ROOT_* de Compose. s3_use_path_style es requerido por MinIO.
# -----------------------------------------------------------------------------
provider "aws" {
  access_key                  = var.minio_access_key
  secret_key                  = var.minio_secret_key
  region                      = var.aws_region
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = var.minio_endpoint
  }
}

# -----------------------------------------------------------------------------
# Alternativa S3 localstack comentada: mismo provider apuntando a LocalStack S3 (:4566).
# Usar solo para practicar IaC multi-servicio AWS; NO como storage del pipeline.
# -----------------------------------------------------------------------------
# provider "aws" {
#   access_key                  = "test"
#   secret_key                  = "test"
#   region                      = var.aws_region
#   skip_credentials_validation = true
#   skip_metadata_api_check     = true
#   skip_requesting_account_id  = true
#
#   endpoints {
#     s3  = var.localstack_endpoint
#     # sqs = var.localstack_endpoint
#     # sns = var.localstack_endpoint
#   }
# }

# -----------------------------------------------------------------------------
# Futuro: provider nativo MinIO para politicas, grupos y usuarios.
# Los buckets pueden seguir con aws_s3_bucket o migrarse a minio_s3_bucket.
# -----------------------------------------------------------------------------
# provider "minio" {
#   minio_server   = replace(var.minio_endpoint, "http://", "")
#   minio_user     = var.minio_access_key
#   minio_password = var.minio_secret_key
#   minio_ssl      = false
# }
#
# resource "minio_iam_user" "etl" {
#   name = "etl-writer"
# }
#
# resource "minio_iam_group" "data_pipeline" {
#   name = "data-pipeline"
# }
#
# resource "minio_iam_policy" "raw_write" {
#   name = "raw-write"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
#       Resource = [
#         "arn:aws:s3:::${local.bucket_prefix}-raw",
#         "arn:aws:s3:::${local.bucket_prefix}-raw/*",
#       ]
#     }]
#   })
# }

# Tres buckets del data lake local en MinIO/ Localstack (equivalente a S3 en AWS):
#   tp-integrador-raw
#   tp-integrador-processed
#   tp-integrador-curated
resource "aws_s3_bucket" "raw" {
  bucket = "${local.bucket_prefix}-raw"
}

resource "aws_s3_bucket" "processed" {
  bucket = "${local.bucket_prefix}-processed"
}

resource "aws_s3_bucket" "curated" {
  bucket = "${local.bucket_prefix}-curated"
}

# SQS comentado: cola de eventos + DLQ sobre LocalStack; deshabilitada por ahora.
# Requiere el provider apuntando a LocalStack (bloque comentado arriba), no a MinIO.
# resource "aws_sqs_queue" "events_dlq" {
#   name                      = "${local.project_name}-events-dlq"
#   message_retention_seconds = 86400
# }
#
# resource "aws_sqs_queue" "events" {
#   name = "${local.project_name}-events"
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
#     maxReceiveCount     = 3
#   })
# }
