variable "enable_ecs_api" { type = bool }
variable "repo_root" { type = string }
variable "sg_efs_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "tags" { type = map(string) }

# Hobby: LocalStack no expone ECS/EFS. Marcamos el stand-in (Compose + bind-mount).
resource "local_file" "efs_standin_marker" {
  filename = "${var.repo_root}/ecs/efs-standin/.iac-managed"
  content  = <<-EOT
    Managed by OpenTofu lab-09-tp (enable_ecs_api=${var.enable_ecs_api}).
    Stand-in path ≈ EFS: ecs/efs-standin/{dags,logs}
    SG modelo NFS :2049 → ${var.sg_efs_id}
    Runtime Hobby → docker compose -f ecs/docker-compose.airflow.yaml up -d
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
    mode              = var.enable_ecs_api ? "aws-api" : "hobby-standin"
    cluster           = try(aws_ecs_cluster.airflow[0].name, null)
    efs_id            = try(aws_efs_file_system.dags[0].id, null)
    standin_dags      = "ecs/efs-standin/dags"
    standin_compose   = "ecs/docker-compose.airflow.yaml"
    execution_role_arn = var.execution_role_arn
    task_role_arn     = var.task_role_arn
    sg_efs            = var.sg_efs_id
  })
}
