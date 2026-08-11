# Lab 06 — OpenTofu: data lake en MinIO (API S3)
# Declara buckets + versioning + SSE-S3 + bucket policies.
# Demos (objeto, versioning mutate, AssumeRole, presign) → s3/s3_demo.py --skip-infra

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
