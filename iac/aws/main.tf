# Lab 09 — IaC con OpenTofu (drop-in de Terraform).
#
# Workflow: tofu init → tofu plan → tofu apply → tofu destroy
#
# Lo que declaramos acá:
#   1. Un bucket S3 para que la app del Dockerfile lea/escriba.
#   2. Versioning ON (decisión heredada del lab 06).
#   3. Un objeto seed (hello.txt) para que el bucket no quede vacío.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider AWS apuntado a LocalStack.
# Para AWS real: borrar el bloque `endpoints` y configurar credenciales reales.
provider "aws" {
  region = var.region

  # Credenciales falsas — LocalStack las ignora
  access_key = "test"
  secret_key = "test"

  # Flags que LocalStack necesita
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = var.localstack_endpoint
    iam = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}

# El bucket — lo MISMO que en lab 06, pero declarado en IaC.
resource "aws_s3_bucket" "app" {
  bucket = var.bucket_name

  tags = {
    Lab       = "09"
    Project   = var.project_name
    ManagedBy = "OpenTofu"
  }
}

# Versioning como decisión por defecto.
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Objeto seed — para que el bucket tenga algo al apply.
resource "aws_s3_object" "hello" {
  bucket  = aws_s3_bucket.app.id
  key     = "hello.txt"
  content = "hello from IaC — bucket ${aws_s3_bucket.app.id}\n"

  tags = {
    Lab = "09"
  }
}
