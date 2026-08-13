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

resource "aws_secretsmanager_secret" "master" {
  name        = "dw/rds-master"
  description = "Master de RDS tp-dw-db — solo bootstrap / admin"
  tags        = var.tags
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

resource "aws_secretsmanager_secret" "etl" {
  name        = "dw/rds-etl"
  description = "Credencial ETL (ECS): escritura bronce + lectura/escritura gold"
  tags        = var.tags
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

resource "aws_secretsmanager_secret" "api" {
  name        = "dw/rds-api"
  description = "Credencial Lambda API: SELECT solo sobre schema gold"
  tags        = var.tags
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

resource "aws_secretsmanager_secret" "origen_demo" {
  name        = "dw/origen-demo"
  description = "Lab 09b — origen demo (postgres-bronce)"
  tags        = var.tags
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

resource "aws_secretsmanager_secret" "erp" {
  name        = "dw/erp"
  description = "Lab extra — origen ERP (postgres-erp)"
  tags        = var.tags
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
