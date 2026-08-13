# =============================================================================
# outputs.tf — Valores de `tofu apply` / `tofu output`
# -----------------------------------------------------------------------------
# =============================================================================

output "function_name" {
  description = "Nombre de la función Lambda"
  value       = aws_lambda_function.gold_api.function_name
}

output "function_arn" {
  description = "ARN de tp-gold-api"
  value       = aws_lambda_function.gold_api.arn
}

output "api_role_arn" {
  description = "ARN del rol api-role"
  value       = aws_iam_role.api.arn
}

output "bi_api_group" {
  description = "Grupo BI que puede Invoke"
  value       = aws_iam_group.bi_api.name
}

output "log_group_name" {
  description = "CloudWatch Log group de la función"
  value       = aws_cloudwatch_log_group.api.name
}

output "attach_vpc" {
  description = "Si el deploy incluyó VpcConfig"
  value       = var.attach_vpc
}

output "sg_api_id" {
  description = "SG de la Lambda (diseño to-be)"
  value       = data.aws_security_groups.api.ids[0]
}

output "compute_subnet_ids" {
  description = "Subnets compute (VpcConfig si attach_vpc)"
  value       = data.aws_subnets.compute.ids
}

output "lambda_inventory_path" {
  description = "JSON inventario en lambda/"
  value       = local_file.lambda_inventory.filename
}

output "next_steps" {
  description = "Ayuda post-apply"
  value       = <<-EOT
    Infra Lambda OK (función ${var.function_name}, attach_vpc=${var.attach_vpc}).
    Runtime Hobby (ALB :8088 + invoke + export logs MinIO):
      python lambda/lambda_demo.py --skip-infra
    Solo ALB omitido:
      python lambda/lambda_demo.py --skip-infra --skip-alb
    Postman:
      GET http://localhost:8088/gold/query?table=dim_cliente&columns=nombre,email&condition=segmento=retail
  EOT
}
