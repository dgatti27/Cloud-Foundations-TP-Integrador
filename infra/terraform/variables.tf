variable "environment" {
  description = "Nombre del entorno."
  type        = string
  default     = "local"
}

variable "aws_region" {
  description = "Region que exige el provider AWS (MinIO la ignora)."
  type        = string
  default     = "us-east-1"
}

variable "minio_endpoint" {
  description = "Endpoint API de MinIO (servicio s3-soporte en Compose)."
  type        = string
  default     = "http://localhost:9000"
}

variable "minio_access_key" {
  description = "Access key de MinIO (MINIO_ROOT_USER)."
  type        = string
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_secret_key" {
  description = "Secret key de MinIO (MINIO_ROOT_PASSWORD)."
  type        = string
  default     = "minioadmin"
  sensitive   = true
}

# Solo si se reactiva el provider LocalStack (S3 / SQS / SNS de practica IaC).
variable "localstack_endpoint" {
  description = "Endpoint de LocalStack (comentado en main.tf; no usar como S3 del pipeline)."
  type        = string
  default     = "http://localhost:4566"
}
