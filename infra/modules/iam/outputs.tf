output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "api_role_arn" {
  value = aws_iam_role.api.arn
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn
}

output "db_role_arn" {
  value = aws_iam_role.db.arn
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
