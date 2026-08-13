# =============================================================================
# variables.tf — Entradas del stack (valores en terraform.tfvars / -var / env)
# -----------------------------------------------------------------------------
# Cada variable es un "tornillo" que podés cambiar sin editar main.tf.
# Defaults = lab local; en prod ajustar endpoint, keys y tags.
# =============================================================================

# ---------------------------------------------------------------------------
# Conexión a MinIO
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "Región AWS formal. MinIO la ignora; el provider/CLI la piden igual."
  default     = "us-east-1"
}

variable "minio_endpoint" {
  type        = string
  description = "URL S3-compatible del servicio Docker s3-soporte (compose)."
  default     = "http://localhost:9000"
}

variable "minio_access_key" {
  type        = string
  description = "Access key MinIO (= MINIO_ROOT_USER). Equivale a AWS_ACCESS_KEY_ID."
  default     = "minioadmin"
  sensitive   = true # no se imprime en logs de plan/apply
}

variable "minio_secret_key" {
  type        = string
  description = "Secret key MinIO (= MINIO_ROOT_PASSWORD). Equivale a AWS_SECRET_ACCESS_KEY."
  default     = "minioadmin"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Qué buckets crear (lab 06)
# ---------------------------------------------------------------------------

variable "lake_buckets" {
  type        = list(string)
  description = <<-EOT
    Nombres de buckets del data lake (lab 06).
    Distintos de *-data-raw (lab 04, demo IAM).
    Cada nombre debe tener un archivo s3/bucket_policy_<nombre>.json.
  EOT
  default = [
    "backup-data-lake",   # backups / dumps / logs export
    "snapshot-data-lake", # snapshots RDS / exports
    "staging-data-lake",  # staging ETL
  ]
}

# ---------------------------------------------------------------------------
# Toggles de comportamiento
# ---------------------------------------------------------------------------

variable "enable_encryption" {
  type        = bool
  description = <<-EOT
    Si true, aplica SSE-S3 (AES256) por defecto en cada bucket.
    En MinIO hace falta KMS (MINIO_KMS_SECRET_KEY en compose).
    Si tofu apply falla con NotImplemented / KMS → poner false.
  EOT
  default     = true
}

variable "upload_seed_object" {
  type        = bool
  description = <<-EOT
    Si true, sube s3/README.md → s3://backup-data-lake/raw/README.md
    (paso 3 del lab). Sirve de base para demo versioning / presign en Python.
  EOT
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes. MinIO puede ignorarlos; en AWS real sirven FinOps/ops."
  default = {
    Project = "TP-Integrador"
    Lab     = "06"
  }
}
