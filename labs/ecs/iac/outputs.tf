# =============================================================================
# outputs.tf — Valores de `tofu apply` / `tofu output`
# -----------------------------------------------------------------------------
# No crean infra: exponen ARNs/IDs para demos y docs.
# =============================================================================

output "mode" {
  description = "hobby-standin (default) o aws-api si enable_ecs_api=true"
  value       = var.enable_ecs_api ? "aws-api" : "hobby-standin"
}

output "execution_role_arn" {
  description = "ARN de ecsTaskExecutionRole (agente boot)"
  value       = aws_iam_role.ecs_execution.arn
}

output "task_role_arn" {
  description = "ARN de app-role (task role; InlineEtlSecrets aplicado)"
  value       = data.aws_iam_role.app.arn
}

output "sg_efs_id" {
  description = "SG EFS del lab 07-v2 (modelo NFS :2049)"
  value       = data.aws_security_groups.efs.ids[0]
}

output "compute_subnet_ids" {
  description = "Subnets Role=ecs-lambda-efs (mount / tasks to-be)"
  value       = data.aws_subnets.compute.ids
}

output "origen_secret_name" {
  description = "Secret origen demo, o null si manage_origen_secret=false"
  value       = try(aws_secretsmanager_secret.origen_demo[0].name, null)
}

output "cluster_name" {
  description = "Cluster ECS si enable_ecs_api; null en Hobby"
  value       = try(aws_ecs_cluster.airflow[0].name, null)
}

output "efs_id" {
  description = "File system EFS si enable_ecs_api; null en Hobby"
  value       = try(aws_efs_file_system.dags[0].id, null)
}

output "efs_inventory_path" {
  description = "JSON inventario escrito en ecs/"
  value       = local_file.efs_inventory.filename
}

output "next_steps" {
  description = "Ayuda post-apply (DX del lab)"
  value       = <<-EOT
    Infra lab-09b OK (mode=${var.enable_ecs_api ? "aws-api" : "hobby-standin"}).
    Runtime Airflow + DAG demo (y --erp):
      python ecs/ecs_demo.py --skip-infra
      python ecs/ecs_demo.py --skip-infra --erp
    UI: http://localhost:8080  (admin / admin)
    Inventario: ecs/efs_inventory.json
  EOT
}
