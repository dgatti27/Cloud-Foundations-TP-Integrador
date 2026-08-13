# =============================================================================
# variables.tf — Entradas del stack (terraform.tfvars / -var / env)
# -----------------------------------------------------------------------------
# Tornillos sin editar main.tf. Defaults = lab-09b Hobby (stand-in).
# =============================================================================

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "Región formal del provider. LocalStack/MiniStack la ignoran; el SDK la pide."
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "URL LocalStack — IAM + lookup VPC/sg-efs (+ ECS/EFS API si enable_ecs_api)."
  default     = "http://localhost:4566"
}

variable "ministack_endpoint" {
  type        = string
  description = "URL MiniStack — secret dw/origen-demo (camino A)."
  default     = "http://localhost:4567"
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

# ---------------------------------------------------------------------------
# Lookup de red (lab 07-v2) — NO se recrea acá
# ---------------------------------------------------------------------------

variable "vpc_name_tag" {
  type        = string
  description = "tag:Name de la VPC (tp-integrador-vpc)."
  default     = "tp-integrador-vpc"
}

variable "sg_efs_name_tag" {
  type        = string
  description = "tag:Name del SG EFS (NFS :2049 to-be). GroupName puede ser tp-efs."
  default     = "sg-efs"
}

variable "compute_subnet_role_tag" {
  type        = string
  description = "tag:Role de subnets compute (mount targets / tasks Fargate to-be)."
  default     = "ecs-lambda-efs"
}

# ---------------------------------------------------------------------------
# IAM (nombres alineados a lab-04 / lab-09b)
# ---------------------------------------------------------------------------

variable "app_role_name" {
  type        = string
  description = "Task role (lab 04). Debe existir; acá solo se agrega InlineEtlSecrets."
  default     = "app-role"
}

variable "execution_role_name" {
  type        = string
  description = "Execution role del agente ECS (boot: ECR + awslogs)."
  default     = "ecsTaskExecutionRole"
}

# ---------------------------------------------------------------------------
# Secret origen demo (camino A)
# ---------------------------------------------------------------------------

variable "manage_origen_secret" {
  type        = bool
  description = <<-EOT
    Si true, publica dw/origen-demo en MiniStack (postgres-bronce).
    Si ya lo creó ecs_demo.py o lab-09-tp, poné false o importá el secret.
  EOT
  default     = true
}

variable "origen_secret_name" {
  type        = string
  description = "Nombre del secret de origen demo."
  default     = "dw/origen-demo"
}

variable "origen_host" {
  type        = string
  description = "Host DNS del origen demo visto desde Airflow (Compose)."
  default     = "postgres-bronce"
}

variable "origen_port" {
  type        = number
  description = "Puerto Postgres del origen demo."
  default     = 5432
}

variable "origen_dbname" {
  type        = string
  description = "DB del origen demo."
  default     = "bronce"
}

variable "origen_username" {
  type        = string
  description = "User del origen demo."
  default     = "postgres"
  sensitive   = true
}

variable "origen_password" {
  type        = string
  description = "Password del origen demo (compose default: postgres)."
  default     = "postgres"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Hobby vs API ECS/EFS
# ---------------------------------------------------------------------------

variable "enable_ecs_api" {
  type        = bool
  description = <<-EOT
    false (Hobby / default) = solo IAM + marcadores stand-in (Compose + efs-standin/).
    true = intenta aws_ecs_cluster + aws_efs_* en LocalStack (suele requerir Pro) o AWS real.
  EOT
  default     = false
}

variable "ecs_cluster_name" {
  type        = string
  description = "Nombre del cluster si enable_ecs_api=true."
  default     = "tp-airflow"
}

variable "efs_creation_token" {
  type        = string
  description = "creation_token idempotente del File System EFS (API)."
  default     = "tp-integrador-efs-09b"
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes."
  default = {
    Project = "TP-Integrador"
    Lab     = "09b-tp"
  }
}
