locals {
  policy_dir = "${path.module}/.."
  seed_src   = "${path.module}/../README.md"
}

# ---------------------------------------------------------------------------
# Buckets del lake (lab 06 paso 1)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "lake" {
  for_each = toset(var.lake_buckets)

  bucket        = each.value
  force_destroy = true # lab: permitir destroy con objetos

  tags = merge(var.tags, {
    Name = each.value
    Tier = "datalake"
  })
}

# ---------------------------------------------------------------------------
# Versioning (lab 06 paso 2) — activar antes de subir data
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# Encryption SSE-S3 (lab 06 paso 1)
# MinIO: necesita KMS en compose. Si apply falla → enable_encryption=false.
# Block Public Access: NO en MinIO (API no soportada) — omitido a propósito.
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
# Bucket policies (lab 06 paso 5) — resource-based
# JSON en s3/bucket_policy_<bucket>.json (principals IAM LocalStack).
# MinIO guarda la policy; enforcement cruzado IAM↔MinIO ≠ AWS real.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id
  policy = file("${local.policy_dir}/bucket_policy_${each.key}.json")

  depends_on = [aws_s3_bucket.lake]
}

# ---------------------------------------------------------------------------
# Objeto semilla opcional (lab 06 paso 3)
# La demo de versioning / presign del Python asume este key si existe.
# ---------------------------------------------------------------------------
resource "aws_s3_object" "seed_readme" {
  count = var.upload_seed_object && contains(var.lake_buckets, "backup-data-lake") ? 1 : 0

  bucket = aws_s3_bucket.lake["backup-data-lake"].id
  key    = "raw/README.md"
  source = local.seed_src
  etag   = filemd5(local.seed_src)

  content_type = "text/markdown"

  depends_on = [
    aws_s3_bucket_versioning.lake,
  ]
}
