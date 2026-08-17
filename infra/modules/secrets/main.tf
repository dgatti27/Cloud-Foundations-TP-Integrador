# =============================================================================
# Secrets Manager (MiniStack) — credenciales RDS + orígenes
# =============================================================================
# Provider: aws.ministack (:4567 en host / :4566 en red Docker).
#
# Cada secret = recurso `aws_secretsmanager_secret` + `…_version` (JSON).
# El JSON lo leen: pipeline (ETL), Lambda query_gold, DAG de comprobación.
#
# Passwords de roles Postgres (etl_writer / api_reader) se alinean después
# con ALTER ROLE en scripts/post_rds.py (null_resource.rds_seed del root).
#
# Host en el JSON = address MiniStack (red Docker). Desde Compose/Airflow
# se overridea con RDS_HOST_OVERRIDE=host.docker.internal.
# =============================================================================

# ---------------------------------------------------------------------------
# Variables de entrada (las arma infra/main.tf)
# ---------------------------------------------------------------------------
variable "tags" { type = map(string) }
variable "db_name" { type = string }
variable "db_port" { type = number }
variable "master_username" { type = string }
variable "master_password" {
  type      = string
  sensitive = true
}
variable "etl_password" {
  type      = string
  sensitive = true
}
variable "api_password" {
  type      = string
  sensitive = true
}
variable "rds_host" { type = string }
variable "origen_demo" {
  type = object({
    host     = string
    port     = number
    dbname   = string
    username = string
    password = string
  })
}
variable "erp" {
  type = object({
    host     = string
    port     = number
    dbname   = string
    username = string
    password = string
  })
}

# ---------------------------------------------------------------------------
# 1) dw/rds-master — usuario master de la instancia (bootstrap / admin)
# Consumo: post_rds.py, ops. NO lo usan DAGs ni Lambda en runtime normal.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "master" {
  name                    = "dw/rds-master"
  description             = "Master de RDS tp-dw-db — solo bootstrap / admin"
  recovery_window_in_days = 0 # Hobby: borrado inmediato (evita ghosts soft-delete)
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
    dbname   = var.db_name
    port     = var.db_port
    engine   = "postgres"
    host     = var.rds_host
  })
}

# ---------------------------------------------------------------------------
# 2) dw/rds-etl — etl_writer (escritura bronce + gold)
# Consumo: pipeline.config.rds_etl_conn / DAGs grupo 1 y 2.
# search_path orienta psql a bronce,gold.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "etl" {
  name                    = "dw/rds-etl"
  description             = "Credencial ETL (ECS): escritura bronce + lectura/escritura gold"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "etl" {
  secret_id = aws_secretsmanager_secret.etl.id
  secret_string = jsonencode({
    username    = "etl_writer"
    password    = var.etl_password
    dbname      = var.db_name
    port        = var.db_port
    engine      = "postgres"
    host        = var.rds_host
    search_path = "bronce,gold,public"
  })
}

# ---------------------------------------------------------------------------
# 3) dw/rds-api — api_reader (SELECT solo gold)
# Consumo: apps/api/query_gold.py (Lambda tp-gold-api).
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "api" {
  name                    = "dw/rds-api"
  description             = "Credencial Lambda API: SELECT solo sobre schema gold"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "api" {
  secret_id = aws_secretsmanager_secret.api.id
  secret_string = jsonencode({
    username    = "api_reader"
    password    = var.api_password
    dbname      = var.db_name
    port        = var.db_port
    engine      = "postgres"
    host        = var.rds_host
    search_path = "gold,public"
  })
}

# ---------------------------------------------------------------------------
# 4) dw/origen-demo — camino A (etl_rds_comprobation)
# Host típico: postgres-bronce en Compose.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "origen_demo" {
  name                    = "dw/origen-demo"
  description             = "Origen demo (postgres-bronce)"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "origen_demo" {
  secret_id = aws_secretsmanager_secret.origen_demo.id
  secret_string = jsonencode({
    host     = var.origen_demo.host
    port     = var.origen_demo.port
    dbname   = var.origen_demo.dbname
    username = var.origen_demo.username
    password = var.origen_demo.password
    engine   = "postgres"
  })
}

# ---------------------------------------------------------------------------
# 5) dw/erp — camino B (extract ERP → bronce)
# Host: postgres-erp (red Docker). Consumo: pipeline.extract.erp_foxpro.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "erp" {
  name                    = "dw/erp"
  description             = "Origen ERP (postgres-erp)"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "erp" {
  secret_id = aws_secretsmanager_secret.erp.id
  secret_string = jsonencode({
    host     = var.erp.host
    port     = var.erp.port
    dbname   = var.erp.dbname
    username = var.erp.username
    password = var.erp.password
    engine   = "postgres"
  })
}
