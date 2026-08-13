# =============================================================================
# main.tf — Recursos del data lake (lab 06)
# -----------------------------------------------------------------------------
# Orden lógico (dependencias OpenTofu las resuelve; comentarios = mapa mental):
#   1) buckets
#   2) versioning  (antes de subir data)
#   3) encryption  (opcional / KMS MinIO)
#   4) bucket policies (resource-based, JSON en s3/)
#   5) objeto semilla README (opcional)
#
# No incluye: AssumeRole, demos de versioning mutate, presign → s3_demo.py
# =============================================================================

# ---------------------------------------------------------------------------
# locals — rutas relativas al módulo
# path.module = directorio s3/iac/
# ---------------------------------------------------------------------------
locals {
  # Carpeta padre s3/ donde viven bucket_policy_*.json y README.md
  policy_dir = "${path.module}/.."
  seed_src   = "${path.module}/../README.md"
}

# ---------------------------------------------------------------------------
# 1) Buckets (lab 06 paso 1)
# for_each sobre el set de nombres → un recurso por bucket.
# force_destroy=true: tofu destroy puede borrar aunque haya objetos (solo lab).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "lake" {
  for_each = toset(var.lake_buckets)

  bucket        = each.value # nombre global del bucket (= each.key)
  force_destroy = true

  tags = merge(var.tags, {
    Name = each.value
    Tier = "datalake"
  })
}

# ---------------------------------------------------------------------------
# 2) Versioning (lab 06 paso 2)
# for_each = mapa de buckets ya creados → misma clave (nombre).
# Enabled: cada PutObject nuevo puede generar VersionId (historial).
# Activar ANTES de subir data de verdad.
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
# Solo si var.enable_encryption=true; si no, for_each vacío = no crea nada.
# AES256 = cifrado del lado servidor con clave gestionada por el storage.
# Block Public Access (PutPublicAccessBlock): omitido — MinIO no lo implementa.
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
# Lee s3/bucket_policy_<bucket>.json (quién puede Get/Put/List sobre ese bucket).
# Principals = ARNs IAM de LocalStack (app-role, usuarios lab 04).
# MinIO PERSISTE la policy (API compatible); el enforcement IAM×MinIO no es
# el de AWS real (ahí identity + resource policy se evalúan juntas).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id
  # each.key = nombre del bucket → archivo bucket_policy_backup-data-lake.json, etc.
  policy = file("${local.policy_dir}/bucket_policy_${each.key}.json")

  depends_on = [aws_s3_bucket.lake]
}

# ---------------------------------------------------------------------------
# 5) Objeto semilla (lab 06 paso 3) — opcional
# count 0|1: no crear si upload_seed_object=false o falta backup-data-lake.
# etag = filemd5 → si cambiás README.md local, el próximo apply actualiza el objeto.
# depends_on versioning: la 1ª versión queda registrada desde el seed.
# ---------------------------------------------------------------------------
resource "aws_s3_object" "seed_readme" {
  count = var.upload_seed_object && contains(var.lake_buckets, "backup-data-lake") ? 1 : 0

  bucket       = aws_s3_bucket.lake["backup-data-lake"].id
  key          = "raw/README.md"
  source       = local.seed_src
  etag         = filemd5(local.seed_src)
  content_type = "text/markdown"

  depends_on = [
    aws_s3_bucket_versioning.lake,
  ]
}
