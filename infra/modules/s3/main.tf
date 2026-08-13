variable "bucket_names" { type = list(string) }
variable "tags" { type = map(string) }

resource "aws_s3_bucket" "lake" {
  for_each = toset(var.bucket_names)
  bucket   = each.value
  tags     = merge(var.tags, { Name = each.value, Tier = "datalake" })
}

resource "aws_s3_bucket_versioning" "lake" {
  for_each = toset(var.bucket_names)
  bucket   = aws_s3_bucket.lake[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# MinIO KMS (compose) habilita SSE-S3 en el lab; en fallo no bloqueamos apply.
resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  for_each = toset(var.bucket_names)
  bucket   = aws_s3_bucket.lake[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
