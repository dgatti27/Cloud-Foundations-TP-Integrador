# Outputs IAM — ARNs/nombres que el root pasa a lambda / ecs / demos.
output "app_role_arn" {
  value = aws_iam_role.app.arn # task role ETL
}

output "api_role_arn" {
  value = aws_iam_role.api.arn # Lambda tp-gold-api
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn # agente boot ECS
}

output "db_role_arn" {
  value = aws_iam_role.db.arn # export RDS → S3
}

output "bi_api_group_name" {
  value = aws_iam_group.bi_api.name
}

output "bi_ops_group_name" {
  value = aws_iam_group.bi_ops.name
}

output "bi_admin_group_name" {
  value = aws_iam_group.bi_admin.name
}
