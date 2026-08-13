# =============================================================================
# variables.tf — Entradas del stack (terraform.tfvars / -var / env)
# -----------------------------------------------------------------------------
# Tornillos sin editar main.tf. Defaults = lab LocalStack.
# =============================================================================

# ---------------------------------------------------------------------------
# Conexión a LocalStack
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "Región formal. AZs = region+a / region+b (ej. us-east-1a)."
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "URL del LocalStack del compose (EC2/VPC/IAM/STS)."
  default     = "http://localhost:4566"
}

variable "aws_access_key" {
  type        = string
  description = "Access key LocalStack (Hobby: test)."
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "Secret key LocalStack (Hobby: test)."
  default     = "test"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Topología
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR de la VPC. Lab: 10.0.0.0/16 → subnets /24 con cidrsubnet(., 8, N)."
  default     = "10.0.0.0/16"
}

variable "enable_nat" {
  type        = bool
  description = <<-EOT
    true = EIP + NAT en public-alb-a + ruta 0.0.0.0/0 en RT compute (ETL → Internet).
    false = sin NAT (útil si LocalStack flaquea; RDS sigue sin salida a Internet).
    En AWS real el NAT cobra aunque no haya tráfico.
  EOT
  default     = true
}

variable "write_vpc_config" {
  type        = bool
  description = <<-EOT
    true = genera ../vpc_config.json (vpc_id, subnets, SGs, nat, endpoint_s3).
    Lo consumen rds_tp_demo, lambda_demo, ecs_demo, efs_config lookups.
  EOT
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags comunes (Name/Role van por recurso). FinOps/ops en AWS real."
  default = {
    Project = "TP-Integrador"
    Lab     = "07-v2"
  }
}
