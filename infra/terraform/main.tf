terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  project_name = "cloud-foundations-lab"
  environment  = var.environment
}

# Provider configurado para LocalStack local.
# En produccion, remover los endpoints y skip_* y usar credenciales reales.
provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = var.aws_region

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3   = var.localstack_endpoint
    sqs  = var.localstack_endpoint
    sns  = var.localstack_endpoint
  }
}

# Buckets del data lake local (equivalente a S3 en AWS)
resource "aws_s3_bucket" "raw" {
  bucket = "${local.project_name}-raw"
}

resource "aws_s3_bucket" "processed" {
  bucket = "${local.project_name}-processed"
}

resource "aws_s3_bucket" "curated" {
  bucket = "${local.project_name}-curated"
}

# Cola de eventos (equivalente a SQS en AWS)
resource "aws_sqs_queue" "events_dlq" {
  name                      = "${local.project_name}-events-dlq"
  message_retention_seconds = 86400
}

resource "aws_sqs_queue" "events" {
  name = "${local.project_name}-events"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}
