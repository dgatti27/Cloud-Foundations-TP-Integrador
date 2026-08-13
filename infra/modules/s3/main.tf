# =============================================================================
# Data lake S3 (MinIO) — lab 06
# -----------------------------------------------------------------------------
# Orden: buckets → versioning → encryption → bucket policies (resource-based).
# Provider en el root: aws.minio (:9000).
# No incluye: AssumeRole, mutate versioning, presign → s3_demo.py
# =============================================================================

variable "bucket_names" { type = list(string) }
variable "tags" { type = map(string) }
variable "enable_encryption" {
  type        = bool
  description = "SSE-S3 AES256. MinIO KMS del compose lo respalda; si falla no bloquea el lake."
  default     = true
}

locals {
  policy_dir = "${path.module}/policies"
}

# ---------------------------------------------------------------------------
# 1) Buckets (lab 06 paso 1)
# for_each sobre el set de nombres → un recurso por bucket (idempotente).
# force_destroy=true: tofu destroy puede borrar aunque haya objetos (solo lab).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "lake" {
  for_each = toset(var.bucket_names)

  bucket        = each.value
  force_destroy = true

  tags = merge(var.tags, {
    Name = each.value
    Tier = "datalake"
  })
}

# ---------------------------------------------------------------------------
# 2) Versioning (lab 06 paso 2) — activar ANTES de subir data real.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# 3) Encryption SSE-S3 (lab 06 paso 1)
# AES256 = cifrado del lado servidor. PutPublicAccessBlock omitido (MinIO).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  for_each = var.enable_encryption ? aws_s3_bucket.lake : {}

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# 4) Bucket policies (lab 06 paso 5) — resource-based
# Principals = ARNs IAM LocalStack (app-role, usuario2-ops, usuario1-admin).
# MinIO persiste la policy; el enforcement IAM×MinIO no es el de AWS real.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "lake" {
  for_each = {
    for name, b in aws_s3_bucket.lake :
    name => b if fileexists("${local.policy_dir}/bucket_policy_${name}.json")
  }

  bucket = each.value.id
  policy = file("${local.policy_dir}/bucket_policy_${each.key}.json")

  depends_on = [aws_s3_bucket.lake]
}
