# =============================================================================
# main.tf — Recursos lab 08-TP (RDS + secrets + seed opcional)
# -----------------------------------------------------------------------------
# Orden lógico (= pasos del lab / rds_tp_demo.py):
#   1) random passwords + (luego) secret master
#   2) data sources LocalStack: VPC / subnets Role=rds / sg-rds  (NO recrea red)
#   3) aws_db_subnet_group Multi-AZ
#   4) aws_db_instance tp-dw-db (MiniStack → Postgres real en Docker)
#   5) secrets etl/api (+ master con host) — MiniStack Secrets Manager
#   6) null_resource seed (opcional) — seed_tp.sql + ALTER ROLE
#   +) bucket MinIO snapshot (opcional)
#
# NO incluye (queda en rds_tp_demo.py --skip-infra):
#   8) verificar privilegios SQL
#   9) create-db-snapshot + pg_dump → MinIO
# =============================================================================

locals {
  # Repo: labs/rds/iac/ → data/rds/seed_tp.sql
  seed_sql_path = "${path.module}/../../../data/rds/seed_tp.sql"

  # Host que va en los JSON de Secrets (apps Compose pueden necesitar override)
  rds_host = var.rds_host_override != "" ? var.rds_host_override : aws_db_instance.dw.address
}

# ---------------------------------------------------------------------------
# Passwords — no van en el repo ni en rds_tp_config.json
# random_password: generadas en el apply y guardadas en el state (sensitive).
# ---------------------------------------------------------------------------
resource "random_password" "master" {
  length  = 20
  special = false # evita quoting raro en docker/psql/Windows
}

resource "random_password" "etl" {
  length  = 20
  special = false
}

resource "random_password" "api" {
  length  = 20
  special = false
}

# ---------------------------------------------------------------------------
# 2) Lookup de red (LocalStack, lab 07-v2) — data sources, no resources
# Si falla: corré vpc/iac (o provision_vpc_v2.sh) antes.
# ---------------------------------------------------------------------------
data "aws_vpc" "tp" {
  provider = aws.localstack

  filter {
    name   = "tag:Name"
    values = [var.vpc_name_tag]
  }
}

data "aws_subnets" "rds" {
  provider = aws.localstack

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp.id]
  }

  filter {
    name   = "tag:Role"
    values = [var.subnet_role_tag]
  }
}

# tag Name=sg-rds (GroupName puede ser tp-rds por límite AWS de prefijo sg-)
data "aws_security_groups" "rds" {
  provider = aws.localstack

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp.id]
  }

  filter {
    name   = "tag:Name"
    values = [var.sg_rds_name_tag]
  }
}

# Guardrail: Multi-AZ necesita ≥2 subnets (idealmente 2 AZs)
check "rds_subnets_multi_az" {
  assert {
    condition     = length(data.aws_subnets.rds.ids) >= 2
    error_message = "Necesito ≥2 subnets con tag Role=${var.subnet_role_tag} en VPC ${var.vpc_name_tag}. Corré lab 07-v2 / vpc/iac."
  }
}

check "sg_rds_found" {
  assert {
    condition     = length(data.aws_security_groups.rds.ids) >= 1
    error_message = "No encuentro SG tag Name=${var.sg_rds_name_tag}. Corré lab 07-v2 / vpc/iac."
  }
}

# ---------------------------------------------------------------------------
# 3) DB subnet group (MiniStack)
# Agrupa private-rds-a/b para que RDS sepa dónde poner primary/standby.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "tp" {
  name        = "tp-rds-subnets"
  description = "DB subnet group Multi-AZ — private-rds-a / private-rds-b (lab 07-v2)"
  subnet_ids  = data.aws_subnets.rds.ids

  tags = merge(var.tags, { Name = "tp-rds-subnets" })
}

# ---------------------------------------------------------------------------
# 4) Instancia RDS (MiniStack → container Postgres)
# Parámetros = to-be TP / rds_tp_config.json (medium, MultiAZ, encrypted, privada).
# skip_final_snapshot: lab local — destroy sin snapshot final obligatorio.
# ---------------------------------------------------------------------------
resource "aws_db_instance" "dw" {
  identifier     = var.db_identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  db_name           = var.db_name
  username          = var.master_username
  password          = random_password.master.result
  port              = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.tp.name
  vpc_security_group_ids = [data.aws_security_groups.rds.ids[0]]

  multi_az                = var.multi_az
  storage_encrypted       = true
  publicly_accessible     = false
  backup_retention_period = var.backup_retention_period

  skip_final_snapshot = true
  apply_immediately   = true

  tags = merge(var.tags, {
    Name = var.db_identifier
  })

  # MiniStack / provider: password y max_allocated_storage generan drift inocuo
  lifecycle {
    ignore_changes = [password, max_allocated_storage]
  }
}

# ---------------------------------------------------------------------------
# Bucket MinIO para dumps (lab paso 9 — el PutObject lo hace Python)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "snapshot" {
  count = var.manage_snapshot_bucket ? 1 : 0

  provider = aws.minio

  bucket        = var.snapshot_bucket
  force_destroy = true

  tags = merge(var.tags, {
    Name = var.snapshot_bucket
    Tier = "snapshot"
  })
}

# ---------------------------------------------------------------------------
# 5) Secrets Manager (MiniStack) — master / etl / api
# JSON shape = el que consumen ECS/Lambda (username, password, host, search_path).
# Las passwords de roles Postgres se alinean en el seed (ALTER ROLE).
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "master" {
  name        = var.secret_master_name
  description = "Master de RDS tp-dw-db — solo bootstrap / admin"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    dbname   = var.db_name
    port     = var.db_port
    engine   = "postgres"
    host     = local.rds_host
  })
}

resource "aws_secretsmanager_secret" "etl" {
  name        = var.secret_etl_name
  description = "Credencial ETL (ECS): escritura bronce + lectura/escritura gold"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "etl" {
  secret_id = aws_secretsmanager_secret.etl.id
  secret_string = jsonencode({
    username    = "etl_writer"
    password    = random_password.etl.result
    dbname      = var.db_name
    port        = var.db_port
    engine      = "postgres"
    host        = local.rds_host
    search_path = "bronce,gold,public"
  })
}

resource "aws_secretsmanager_secret" "api" {
  name        = var.secret_api_name
  description = "Credencial Lambda API: SELECT solo sobre schema gold"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "api" {
  secret_id = aws_secretsmanager_secret.api.id
  secret_string = jsonencode({
    username    = "api_reader"
    password    = random_password.api.result
    dbname      = var.db_name
    port        = var.db_port
    engine      = "postgres"
    host        = local.rds_host
    search_path = "gold,public"
  })
}

# ---------------------------------------------------------------------------
# 6) Seed SQL + ALTER ROLE (opcional)
# Equivale a pasos 6–7 del demo Python, vía docker exec al container MiniStack.
# triggers: re-corre si cambia instancia, passwords o el archivo seed_tp.sql.
# ---------------------------------------------------------------------------
resource "null_resource" "rds_seed" {
  count = var.apply_rds_seed ? 1 : 0

  triggers = {
    db_id         = aws_db_instance.dw.id
    master_hash   = sha256(random_password.master.result)
    etl_hash      = sha256(random_password.etl.result)
    api_hash      = sha256(random_password.api.result)
    seed_checksum = filesha256(local.seed_sql_path)
  }

  provisioner "local-exec" {
    working_dir = path.module
    environment = {
      POST_RDS_MASTER_PASSWORD = random_password.master.result
      POST_RDS_ETL_PASSWORD    = random_password.etl.result
      POST_RDS_API_PASSWORD    = random_password.api.result
      POST_RDS_SEED            = replace(abspath(local.seed_sql_path), "\\", "/")
      POST_RDS_IDENTIFIER      = var.db_identifier
      POST_RDS_MASTER_USER     = var.master_username
      POST_RDS_DBNAME          = var.db_name
    }
    # -u: stdout sin buffer (mejor en Windows / tofu logs)
    command = "python -u scripts/post_rds.py"
  }

  depends_on = [
    aws_db_instance.dw,
    aws_secretsmanager_secret_version.master,
    aws_secretsmanager_secret_version.etl,
    aws_secretsmanager_secret_version.api,
  ]
}
