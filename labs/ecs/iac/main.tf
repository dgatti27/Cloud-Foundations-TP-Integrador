# =============================================================================
# main.tf — Recursos lab 09b-TP (IAM modelo + stand-in + secret + API opcional)
# -----------------------------------------------------------------------------
# Orden lógico (= pasos del lab / ecs_demo.py):
#   0) data: app-role (lab 04) + VPC / sg-efs / subnets compute (lab 07-v2)
#   1) ecsTaskExecutionRole + InlineEcsExecution
#      InlineEtlSecrets en app-role (task role)
#   2) marcadores efs-standin/ + efs_inventory.json (Hobby ≈ EFS)
#   3) secret dw/origen-demo (MiniStack, opcional)
#   +) si enable_ecs_api: cluster ECS + EFS FS + mount targets
#
# NO incluye (queda en ecs_demo.py --skip-infra):
#   Compose Airflow up, parse/trigger DAG, verify bronce, camino ERP, cleanup
# =============================================================================

locals {
  # Policies JSON del lab viven en labs/ecs/ (padre de iac/)
  ecs_dir = "${path.module}/.."
  airflow_dir = "${path.module}/../../../apps/airflow"

  # Paths stand-in ≈ access points /airflow/dags y /airflow/logs
  standin_dags = "${local.airflow_dir}/dags"
  standin_logs = "${local.airflow_dir}/logs"
}

# ---------------------------------------------------------------------------
# 0) Lookups — prereqs de labs previos (fallan claro si faltan)
# ---------------------------------------------------------------------------

# Task role base del lab 04 (trust ECS + InlineS3Read). Acá NO lo creamos.
data "aws_iam_role" "app" {
  name = var.app_role_name
}

data "aws_vpc" "tp" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name_tag]
  }
}

data "aws_security_groups" "efs" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp.id]
  }

  filter {
    name   = "tag:Name"
    values = [var.sg_efs_name_tag]
  }
}

data "aws_subnets" "compute" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp.id]
  }

  filter {
    name   = "tag:Role"
    values = [var.compute_subnet_role_tag]
  }
}

check "sg_efs_found" {
  assert {
    condition     = length(data.aws_security_groups.efs.ids) >= 1
    error_message = "No encuentro SG tag Name=${var.sg_efs_name_tag}. Corré lab 07-v2 / vpc/iac."
  }
}

check "compute_subnets" {
  assert {
    condition     = length(data.aws_subnets.compute.ids) >= 1
    error_message = "No encuentro subnets Role=${var.compute_subnet_role_tag}. Corré lab 07-v2 / vpc/iac."
  }
}

# ---------------------------------------------------------------------------
# 1.1) Execution role — agente ECS al boot (ECR + awslogs)
# En Hobby Compose usa keys test/test; el rol documenta el to-be Fargate.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution" {
  name               = var.execution_role_name
  assume_role_policy = file("${local.ecs_dir}/trust_ecs.json")
  description        = "Lab 09b — agente ECS (boot): ECR + awslogs"
  tags               = var.tags
}

resource "aws_iam_role_policy" "ecs_execution" {
  name   = "InlineEcsExecution"
  role   = aws_iam_role.ecs_execution.id
  policy = file("${local.ecs_dir}/execution_policy.json")
}

# ---------------------------------------------------------------------------
# 1.2) Task role — ampliar app-role con lectura de secrets ETL/orígenes
# Privilegio mínimo: NO master/api (Solution §4.1 / IAM-NOTES.md).
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "app_etl_secrets" {
  name   = "InlineEtlSecrets"
  role   = data.aws_iam_role.app.name
  policy = file("${local.ecs_dir}/task_secrets_policy.json")
}

# ---------------------------------------------------------------------------
# 2) EFS stand-in (Hobby) — directorios + marcador + inventario
# Sin create-file-system: Community no incluye EFS. El bind-mount de Compose
# cumple el contrato pedagógico (DAGs/logs compartidos).
# ---------------------------------------------------------------------------
resource "local_file" "efs_standin_marker" {
  filename = "${local.airflow_dir}/.iac-managed"
  content  = <<-EOT
    Managed by OpenTofu labs/ecs/iac (enable_ecs_api=${var.enable_ecs_api}).
    Stand-in path ≈ EFS: apps/airflow/{dags,logs}
    SG modelo NFS :2049 → ${data.aws_security_groups.efs.ids[0]}
    Subnets compute (Role=${var.compute_subnet_role_tag}): ${join(", ", data.aws_subnets.compute.ids)}
    Runtime Hobby → docker compose up -d   # raíz: servicios airflow-*
    Demos → python labs/ecs/ecs_demo.py --skip-infra
  EOT
}

# Asegura que exista el árbol logs/ aunque esté vacío (dags/ ya trae los .py)
resource "local_file" "efs_logs_keep" {
  filename = "${local.standin_logs}/.iac-keep"
  content  = "ecs/iac — access point stand-in /airflow/logs\n"
}

resource "local_file" "efs_inventory" {
  filename = "${local.ecs_dir}/efs_inventory.json"
  content = jsonencode({
    mode                 = var.enable_ecs_api ? "aws-api" : "hobby-standin"
    lab                  = "09b-tp"
    cluster              = try(aws_ecs_cluster.airflow[0].name, null)
    efs_id               = try(aws_efs_file_system.dags[0].id, null)
    standin_dags         = "apps/airflow/dags"
    standin_logs         = "apps/airflow/logs"
    standin_compose      = "compose.yaml (airflow-*)"
    execution_role_arn   = aws_iam_role.ecs_execution.arn
    task_role_arn        = data.aws_iam_role.app.arn
    task_role_policy     = "InlineEtlSecrets"
    sg_efs               = data.aws_security_groups.efs.ids[0]
    compute_subnet_ids   = data.aws_subnets.compute.ids
    origen_secret        = var.manage_origen_secret ? var.origen_secret_name : null
    notes                = "Inventario generado por ecs/iac. Runtime = Compose / ecs_demo.py."
  })

  depends_on = [
    aws_iam_role_policy.ecs_execution,
    aws_iam_role_policy.app_etl_secrets,
    local_file.efs_standin_marker,
  ]
}

# ---------------------------------------------------------------------------
# 3) Secret origen demo (MiniStack) — camino A
# Mismo payload que ecs_demo.ORIGEN_PAYLOAD. dw/rds-etl = lab 08 (prereq).
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "origen_demo" {
  count = var.manage_origen_secret ? 1 : 0

  provider = aws.ministack

  name        = var.origen_secret_name
  description = "Lab 09b — origen demo (postgres-bronce)"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "origen_demo" {
  count = var.manage_origen_secret ? 1 : 0

  provider = aws.ministack

  secret_id = aws_secretsmanager_secret.origen_demo[0].id
  secret_string = jsonencode({
    host     = var.origen_host
    port     = var.origen_port
    dbname   = var.origen_dbname
    username = var.origen_username
    password = var.origen_password
    engine   = "postgres"
  })
}

# ---------------------------------------------------------------------------
# Opcional — API ECS/EFS (LocalStack Pro / AWS real)
# Hobby: enable_ecs_api=false (default). El runtime sigue siendo Compose.
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "airflow" {
  count = var.enable_ecs_api ? 1 : 0

  name = var.ecs_cluster_name
  tags = merge(var.tags, { Name = var.ecs_cluster_name })
}

resource "aws_efs_file_system" "dags" {
  count = var.enable_ecs_api ? 1 : 0

  creation_token = var.efs_creation_token
  encrypted      = true
  tags           = merge(var.tags, { Name = "tp-efs-dags" })
}

resource "aws_efs_mount_target" "compute" {
  count = var.enable_ecs_api ? length(data.aws_subnets.compute.ids) : 0

  file_system_id  = aws_efs_file_system.dags[0].id
  subnet_id       = data.aws_subnets.compute.ids[count.index]
  security_groups = [data.aws_security_groups.efs.ids[0]]
}
