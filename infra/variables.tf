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
  type    = string
  default = "test"
}

variable "aws_secret_key" {
  type      = string
  default   = "test"
  sensitive = true
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "ministack_endpoint" {
  type    = string
  default = "http://localhost:4567"
}

variable "minio_endpoint" {
  type    = string
  default = "http://localhost:9000"
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

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

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

variable "lake_buckets" {
  type        = list(string)
  description = "Buckets del data lake en MinIO."
  default     = ["backup-data-lake", "snapshot-data-lake", "staging-data-lake"]
}

variable "lambda_function_name" {
  type    = string
  default = "tp-gold-api"
}

variable "enable_nat" {
  type        = bool
  description = "NAT Gateway + ruta 0.0.0.0/0 en subnets compute."
  default     = true
}

variable "enable_ecs_api" {
  type        = bool
  description = <<-EOT
    true = declarar ECS cluster / EFS vía API (AWS real o LocalStack Pro).
    false (Hobby) = solo IAM + marcadores stand-in (Compose Airflow + apps/airflow/).
  EOT
  default     = false
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

variable "apply_rds_seed" {
  type        = bool
  description = "Ejecutar seed_tp.sql + roles vía scripts/post_rds.py tras crear RDS."
  default     = true
}

variable "repo_root" {
  type        = string
  description = "Raíz del repo (para paths a seed SQL, apps/api, apps/airflow)."
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
