# =============================================================================
# RDS PostgreSQL Multi-AZ — MiniStack → container Postgres
# -----------------------------------------------------------------------------
# Subnet group + instancia. Secrets y seed viven en el root (modules/secrets
# + null_resource.rds_seed) para no duplicar passwords/state.
#
# Parámetros = to-be TP (medium, MultiAZ, encrypted, privada).
# skip_final_snapshot: entorno local — destroy sin snapshot final obligatorio.
# =============================================================================

variable "identifier" { type = string }
variable "engine_version" {
  type    = string
  default = "16.3"
}
variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "db_name" { type = string }
variable "master_username" { type = string }
variable "master_password" {
  type      = string
  sensitive = true
}
variable "subnet_ids" { type = list(string) }
variable "vpc_security_group_ids" { type = list(string) }
variable "tags" { type = map(string) }

# ---------------------------------------------------------------------------
# DB subnet group — agrupa private-rds-a/b (Multi-AZ primary/standby).
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "tp" {
  name        = "tp-rds-subnets"
  description = "DB subnet group Multi-AZ — private-rds-a / private-rds-b"
  subnet_ids  = var.subnet_ids
  tags        = merge(var.tags, { Name = "tp-rds-subnets" })
}

# ---------------------------------------------------------------------------
# Instancia RDS (MiniStack → Postgres real en Docker)
# ---------------------------------------------------------------------------
resource "aws_db_instance" "dw" {
  identifier              = var.identifier
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_name                 = var.db_name
  username                = var.master_username
  password                = var.master_password
  port                    = 5432
  db_subnet_group_name    = aws_db_subnet_group.tp.name
  vpc_security_group_ids  = var.vpc_security_group_ids
  multi_az                = true
  storage_encrypted       = true
  publicly_accessible     = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = merge(var.tags, { Name = var.identifier })

  # MiniStack / provider: password y max_allocated_storage generan drift inocuo.
  lifecycle {
    ignore_changes = [password, max_allocated_storage]
  }
}
