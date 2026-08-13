# =============================================================================
# variables.tf — Entradas del stack (terraform.tfvars / -var / env)
# -----------------------------------------------------------------------------
# Cada variable es un "tornillo" que podés cambiar sin editar main.tf.
# Defaults = lab local (LocalStack + MinIO del compose).
# =============================================================================

# ---------------------------------------------------------------------------
# Conexión a LocalStack (IAM / STS)
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "Región formal del provider. LocalStack/MinIO la ignoran; el SDK la pide."
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "URL de LocalStack (compose). Ahí viven grupos, users, roles y policies."
  default     = "http://localhost:4566"
}

variable "aws_access_key" {
  type        = string
  description = "Access key dummy de LocalStack (awslocal usa test/test)."
  default     = "test"
  sensitive   = true # no se imprime en logs de plan/apply
}

variable "aws_secret_key" {
  type        = string
  description = "Secret key dummy de LocalStack."
  default     = "test"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Conexión a MinIO (buckets *-data-raw del lab 04)
# ---------------------------------------------------------------------------

variable "minio_endpoint" {
  type        = string
  description = "URL S3-compatible del servicio Docker s3-soporte (compose)."
  default     = "http://localhost:9000"
}

variable "minio_access_key" {
  type        = string
  description = "Access key MinIO (= MINIO_ROOT_USER). Equivale a AWS_ACCESS_KEY_ID."
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_secret_key" {
  type        = string
  description = "Secret key MinIO (= MINIO_ROOT_PASSWORD). Equivale a AWS_SECRET_ACCESS_KEY."
  default     = "minioadmin"
  sensitive   = true
}

variable "raw_buckets" {
  type        = list(string)
  description = <<-EOT
    Nombres de buckets de referencia del lab 04 (recurso "protegido" en las policies JSON).
    Distintos de *-data-lake (lab 06 / s3/iac).
    Las policies en iam/*.json usan ARNs arn:aws:s3:::estos-nombres — si renombrás acá,
    actualizá también esos JSON.
  EOT
  default = [
    "backup-data-raw",
    "snapshot-data-raw",
    "staging-data-raw",
  ]
}

# ---------------------------------------------------------------------------
# Toggles de comportamiento
# ---------------------------------------------------------------------------

variable "manage_minio_buckets" {
  type        = bool
  description = <<-EOT
    Si true, crea los buckets *-data-raw en MinIO (+ seed si upload_seed_object).
    Si ya los creaste a mano / con iam_demo.py / o no querés que este stack los gestione:
    poner false → solo aplica IAM en LocalStack.
  EOT
  default     = true
}

variable "upload_seed_object" {
  type        = bool
  description = <<-EOT
    Si true (y manage_minio_buckets), sube sample/hello.txt a cada bucket raw
    (mismo contenido que iam_demo.ensure_buckets). Sirve para el list del paso 7.
  EOT
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags en roles/users. LocalStack puede ignorarlos; en AWS real sirven FinOps/ops."
  default = {
    Project = "TP-Integrador"
    Lab     = "04"
  }
}
