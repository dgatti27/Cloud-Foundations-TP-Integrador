# =============================================================================
# variables.tf — Entradas del stack (terraform.tfvars / -var / env)
# -----------------------------------------------------------------------------
# Tornillos sin editar main.tf. Defaults = lab-api-tp / Hobby.
# =============================================================================

# ---------------------------------------------------------------------------
# Conexión LocalStack
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "Región formal. LocalStack la ignora; el SDK la pide."
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "URL LocalStack — IAM, Lambda, Logs, lookup VPC."
  default     = "http://localhost:4566"
}

variable "aws_access_key" {
  type        = string
  description = "Access key dummy LocalStack (test)."
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "Secret key dummy LocalStack (test)."
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

variable "sg_api_name_tag" {
  type        = string
  description = "tag:Name del SG de la Lambda (sg-api). GroupName puede ser tp-api."
  default     = "sg-api"
}

variable "compute_subnet_role_tag" {
  type        = string
  description = "tag:Role de subnets compute (private-compute-a/b)."
  default     = "ecs-lambda-efs"
}

# ---------------------------------------------------------------------------
# Función Lambda
# ---------------------------------------------------------------------------

variable "function_name" {
  type        = string
  description = "Nombre de la función (tp-gold-api)."
  default     = "tp-gold-api"
}

variable "lambda_runtime" {
  type        = string
  description = "Runtime Python de la función."
  default     = "python3.12"
}

variable "lambda_timeout" {
  type        = number
  description = "Timeout en segundos."
  default     = 30
}

variable "lambda_memory_mb" {
  type        = number
  description = "Memoria en MB."
  default     = 256
}

variable "attach_vpc" {
  type        = bool
  description = <<-EOT
    true = VpcConfig con subnets compute + sg-api (diseño to-be).
    false (default Hobby) = deploy sin VPC si LocalStack flaquea con ENI.
    El diseño de red queda documentado en outputs / inventario igual.
  EOT
  default     = false
}

variable "include_pg8000" {
  type        = bool
  description = <<-EOT
    true = build zip con pip install pg8000 (necesario para query_gold en runtime).
    false = solo handler.py + query_gold.py (como infra/modules/lambda; invoke puede fallar).
  EOT
  default     = true
}

# Env que ve el runtime Lambda (Docker LocalStack → host)
variable "secrets_endpoint_from_runtime" {
  type        = string
  description = "SECRETS_ENDPOINT desde el container Lambda → MiniStack en el host."
  default     = "http://host.docker.internal:4567"
}

variable "rds_host_override" {
  type        = string
  description = "RDS_HOST_OVERRIDE (Postgres publicado por MiniStack en el host)."
  default     = "host.docker.internal"
}

variable "rds_port_override" {
  type        = number
  description = "Puerto host del Postgres MiniStack (compose map tipico 15432)."
  default     = 15432
}

variable "api_secret_name" {
  type        = string
  description = "Nombre del secret en MiniStack (solo lectura; creado en lab 08)."
  default     = "dw/rds-api"
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

variable "api_role_name" {
  type        = string
  description = "Rol que asume Lambda (api-role)."
  default     = "api-role"
}

variable "bi_api_group_name" {
  type        = string
  description = "Grupo consumidores BI (Invoke; Deny secrets ETL/master)."
  default     = "bi-api"
}

variable "attach_bi_ops_invoke" {
  type        = bool
  description = <<-EOT
    true = pone InlineInvokeGoldApi también en bi-ops (lab 04).
    false si bi-ops aún no existe.
  EOT
  default     = true
}

variable "bi_ops_group_name" {
  type        = string
  description = "Grupo ops del lab 04."
  default     = "bi-ops"
}

variable "log_retention_days" {
  type        = number
  description = "Retención del log group (lab local: corta)."
  default     = 7
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes."
  default = {
    Project = "TP-Integrador"
    Lab     = "api-tp"
  }
}
