variable "region" {
  type        = string
  description = "Región AWS (MinIO la ignora; el CLI/SDK la piden)."
  default     = "us-east-1"
}

variable "minio_endpoint" {
  type        = string
  description = "URL S3-compatible de MinIO (compose s3-soporte)."
  default     = "http://localhost:9000"
}

variable "minio_access_key" {
  type        = string
  description = "MINIO_ROOT_USER"
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_secret_key" {
  type        = string
  description = "MINIO_ROOT_PASSWORD"
  default     = "minioadmin"
  sensitive   = true
}

variable "lake_buckets" {
  type        = list(string)
  description = "Buckets del data lake (lab 06). *-data-raw son del lab 04 IAM."
  default = [
    "backup-data-lake",
    "snapshot-data-lake",
    "staging-data-lake",
  ]
}

variable "enable_encryption" {
  type        = bool
  description = "SSE-S3 (AES256). En MinIO requiere MINIO_KMS_SECRET_KEY en compose; si falla, poné false."
  default     = true
}

variable "upload_seed_object" {
  type        = bool
  description = "Sube s3/README.md → backup-data-lake/raw/README.md (paso 3 del lab)."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes (MinIO puede ignorarlos; útiles en AWS real)."
  default = {
    Project = "TP-Integrador"
    Lab     = "06"
  }
}
