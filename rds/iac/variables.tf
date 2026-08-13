# =============================================================================
# variables.tf — Entradas del stack (terraform.tfvars / -var / env)
# -----------------------------------------------------------------------------
# Tornillos sin editar main.tf. Defaults = lab-08-tp / rds_tp_config.json.
# =============================================================================

# ---------------------------------------------------------------------------
# Endpoints de emuladores
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "Región formal del provider. MiniStack/LocalStack/MinIO la ignoran; el SDK la pide."
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "URL LocalStack — lookup VPC/subnets/sg-rds (lab 07-v2)."
  default     = "http://localhost:4566"
}

variable "ministack_endpoint" {
  type        = string
  description = "URL MiniStack — RDS Postgres real + Secrets Manager DB."
  default     = "http://localhost:4567"
}

variable "minio_endpoint" {
  type        = string
  description = "URL MinIO — bucket snapshot-data-lake (decisión 002)."
  default     = "http://localhost:9000"
}

variable "aws_access_key" {
  type        = string
  description = "Access key dummy LocalStack/MiniStack (test)."
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "Secret key dummy LocalStack/MiniStack (test)."
  default     = "test"
  sensitive   = true
}

variable "minio_access_key" {
  type        = string
  description = "MINIO_ROOT_USER (compose default: minioadmin)."
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_secret_key" {
  type        = string
  description = "MINIO_ROOT_PASSWORD (compose default: minioadmin)."
  default     = "minioadmin"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Lookup de red (lab 07-v2) — NO se recrea acá
# ---------------------------------------------------------------------------

variable "vpc_name_tag" {
  type        = string
  description = "tag:Name de la VPC a buscar en LocalStack (tp-integrador-vpc)."
  default     = "tp-integrador-vpc"
}

variable "subnet_role_tag" {
  type        = string
  description = "tag:Role de las subnets RDS (private-rds-a/b). Debe haber ≥2 AZs."
  default     = "rds"
}

variable "sg_rds_name_tag" {
  type        = string
  description = "tag:Name del SG RDS (sg-rds). GroupName en IaC VPC puede ser tp-rds."
  default     = "sg-rds"
}

# ---------------------------------------------------------------------------
# Instancia RDS (alineado a rds_tp_config.json)
# ---------------------------------------------------------------------------

variable "db_identifier" {
  type        = string
  description = "DBInstanceIdentifier (tp-dw-db)."
  default     = "tp-dw-db"
}

variable "engine_version" {
  type        = string
  description = "Versión Postgres (MiniStack)."
  default     = "16.3"
}

variable "instance_class" {
  type        = string
  description = "Clase de instancia. To-be TP: db.t3.medium."
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  type        = number
  description = "Disco inicial en GiB."
  default     = 50
}

variable "db_name" {
  type        = string
  description = "Base inicial. Una sola DB 'dw' con schemas bronce + gold (seed)."
  default     = "dw"
}

variable "master_username" {
  type        = string
  description = "Usuario admin bootstrap (dwadmin). No lo usan ETL/Lambda en runtime."
  default     = "dwadmin"
}

variable "db_port" {
  type        = number
  description = "Puerto Postgres."
  default     = 5432
}

variable "backup_retention_period" {
  type        = number
  description = "Días de retención de backups automáticos."
  default     = 7
}

variable "multi_az" {
  type        = bool
  description = "true = standby en otra AZ (to-be TP). Requiere subnet group Multi-AZ."
  default     = true
}

# ---------------------------------------------------------------------------
# Secrets (nombres en MiniStack Secrets Manager)
# ---------------------------------------------------------------------------

variable "secret_master_name" {
  type        = string
  description = "Path del secret master (bootstrap / seed / dump)."
  default     = "dw/rds-master"
}

variable "secret_etl_name" {
  type        = string
  description = "Path del secret ETL (ECS → etl_writer)."
  default     = "dw/rds-etl"
}

variable "secret_api_name" {
  type        = string
  description = "Path del secret API (Lambda → api_reader)."
  default     = "dw/rds-api"
}

# ---------------------------------------------------------------------------
# Toggles
# ---------------------------------------------------------------------------

variable "manage_snapshot_bucket" {
  type        = bool
  description = <<-EOT
    Si true, crea el bucket snapshot-data-lake en MinIO (force_destroy lab).
    Default false: suele existir vía s3/iac (lab 06). Poné true solo si aún no está.
    El dump pg_dump→PutObject sigue en rds_tp_demo.py --skip-infra.
  EOT
  default     = false
}

variable "snapshot_bucket" {
  type        = string
  description = "Nombre del bucket de dumps (MinIO)."
  default     = "snapshot-data-lake"
}

variable "apply_rds_seed" {
  type        = bool
  description = <<-EOT
    Si true, tras create-db-instance corre scripts/post_rds.py:
    seed_tp.sql + ALTER ROLE passwords alineadas a Secrets.
    Requiere Docker + container MiniStack de la instancia.
    Si false: solo infra API; aplicá seed con Python (full o flags).
  EOT
  default     = true
}

variable "rds_host_override" {
  type        = string
  description = <<-EOT
    Si no vacío, host escrito en los secrets en lugar de aws_db_instance.address.
    Útil si Compose/apps ven otro hostname Docker que el address MiniStack.
  EOT
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes (Name/Lab van por recurso)."
  default = {
    Project = "TP-Integrador"
    Lab     = "08-tp"
  }
}
