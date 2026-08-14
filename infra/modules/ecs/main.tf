# =============================================================================
# ECS / EFS del TP
# -----------------------------------------------------------------------------
# Hobby (enable_ecs_api=false, default): LocalStack no expone APIs ecs/efs.
#   → marcador apps/airflow/.iac-managed + inventario JSON.
#   Runtime = Compose airflow-* (mismo contrato pedagógico que Fargate + EFS).
#
# AWS real / LocalStack Pro (enable_ecs_api=true):
#   → cluster + EFS + mount targets en subnets compute.
#
# IAM execution/task roles los crea modules/iam. Secret origen = modules/secrets.
# Compose / trigger DAG = ecs.py --skip-infra (no IaC).
# =============================================================================

variable "enable_ecs_api" { type = bool }
variable "repo_root" { type = string }
variable "sg_efs_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "tags" { type = map(string) }

# Stand-in Hobby ≈ access points /airflow/dags y /airflow/logs
resource "local_file" "efs_standin_marker" {
  filename = "${var.repo_root}/apps/airflow/.iac-managed"
  content  = <<-EOT
    Managed by OpenTofu (enable_ecs_api=${var.enable_ecs_api}).
    Stand-in path ≈ EFS: apps/airflow/{dags,logs}
    SG modelo NFS :2049 → ${var.sg_efs_id}
    Runtime Hobby → docker compose up -d   # raíz: servicios airflow-*
  EOT
}

resource "aws_ecs_cluster" "airflow" {
  count = var.enable_ecs_api ? 1 : 0
  name  = "tp-airflow"
  tags  = merge(var.tags, { Name = "tp-airflow" })
}

resource "aws_efs_file_system" "dags" {
  count          = var.enable_ecs_api ? 1 : 0
  creation_token = "tp-integrador-efs"
  encrypted      = true
  tags           = merge(var.tags, { Name = "tp-efs-dags" })
}

resource "aws_efs_mount_target" "compute" {
  count           = var.enable_ecs_api ? length(var.subnet_ids) : 0
  file_system_id  = aws_efs_file_system.dags[0].id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [var.sg_efs_id]
}

resource "local_file" "ecs_inventory" {
  filename = "${path.module}/../../generated/ecs_inventory.json"
  content = jsonencode({
    mode               = var.enable_ecs_api ? "aws-api" : "hobby-standin"
    cluster            = try(aws_ecs_cluster.airflow[0].name, null)
    efs_id             = try(aws_efs_file_system.dags[0].id, null)
    standin_dags       = "apps/airflow/dags"
    standin_compose    = "compose.yaml (airflow-*)"
    execution_role_arn = var.execution_role_arn
    task_role_arn      = var.task_role_arn
    sg_efs             = var.sg_efs_id
  })
}
