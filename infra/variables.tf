# =============================================================================
# Variables del root module (inputs de tofu)
# =============================================================================
# Overrides: terraform.tfvars (gitignore) o -var / TF_VAR_*.
# Ejemplo: terraform.tfvars.example
#
# Desde la toolbox Compose, varios TF_VAR_* se inyectan (endpoints Docker).
# =============================================================================

# ---------------------------------------------------------------------------
# Proyecto / región / credenciales dummy Hobby
# ---------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Slug del proyecto (tags)."
  default     = "tp-integrador"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "aws_access_key" {
  type        = string
  description = "Access key hacia LocalStack/MiniStack (Hobby: test)."
  default     = "test"
}

variable "aws_secret_key" {
  type        = string
  default     = "test"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Endpoints de los tres backends (host local por defecto)
# Toolbox: TF_VAR_* apunta a nombres Docker (localstack-integrador:4566, …).
# ---------------------------------------------------------------------------
variable "localstack_endpoint" {
  type        = string
  description = "IAM, VPC, Lambda, CloudWatch, STS."
  default     = "http://localhost:4566"
}

variable "ministack_endpoint" {
  type        = string
  description = "RDS + Secrets Manager (DB)."
  default     = "http://localhost:4567"
}

variable "minio_endpoint" {
  type        = string
  description = "S3 API del data lake."
  default     = "http://localhost:9000"
}

variable "minio_access_key" {
  type    = string
  default = "minioadmin"
}

variable "minio_secret_key" {
  type      = string
  default   = "minioadmin"
  sensitive = true
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "enable_nat" {
  type        = bool
  description = "NAT Gateway + ruta 0.0.0.0/0 en subnets compute (salida ETL)."
  default     = true
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------
variable "db_identifier" {
  type    = string
  default = "tp-dw-db"
}

variable "db_name" {
  type    = string
  default = "dw"
}

variable "db_master_username" {
  type    = string
  default = "dwadmin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "db_allocated_storage" {
  type    = number
  default = 50
}

variable "apply_rds_seed" {
  type        = bool
  description = "Tras crear RDS: seed_tp.sql + ALTER ROLE vía scripts/post_rds.py."
  default     = true
}

variable "rds_host_override" {
  type        = string
  description = "Host que apps en Docker usan para llegar a RDS (host.docker.internal)."
  default     = "host.docker.internal"
}

variable "rds_port_override" {
  type        = number
  description = "Puerto host publicado por MiniStack para Postgres RDS."
  default     = 15432
}

# ---------------------------------------------------------------------------
# Data lake (MinIO)
# ---------------------------------------------------------------------------
variable "lake_buckets" {
  type        = list(string)
  description = "Buckets del data lake en MinIO."
  default     = ["backup-data-lake", "snapshot-data-lake", "staging-data-lake"]
}

# ---------------------------------------------------------------------------
# Lambda / ECS
# ---------------------------------------------------------------------------
variable "lambda_function_name" {
  type    = string
  default = "tp-gold-api"
}

variable "enable_ecs_api" {
  type        = bool
  description = <<-EOT
    true = declarar ECS cluster / EFS vía API (AWS real o LocalStack Pro).
    false (Hobby) = solo IAM + marcadores stand-in (Compose Airflow + apps/airflow/).
  EOT
  default = false
}

# ---------------------------------------------------------------------------
# Paths / FinOps
# ---------------------------------------------------------------------------
variable "repo_root" {
  type        = string
  description = "Raíz del repo relativa a infra/ (seed SQL, apps/api, apps/airflow)."
  default     = ".."
}

variable "create_budget" {
  type        = bool
  description = "AWS Budget real. false en Hobby (LocalStack no tiene Budgets usable)."
  default     = false
}

variable "finops_notify_email" {
  type        = string
  description = "Email de alertas del Budget. Obligatorio si create_budget=true."
  default     = "you@example.com"
}
