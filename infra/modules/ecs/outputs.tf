# Outputs ECS — mode hobby-standin | aws-api (+ cluster/efs si aplica).
output "mode" {
  value = var.enable_ecs_api ? "aws-api" : "hobby-standin"
}

output "cluster_name" {
  value = try(aws_ecs_cluster.airflow[0].name, null)
}

output "efs_id" {
  value = try(aws_efs_file_system.dags[0].id, null)
}
