# Outputs Lambda — nombre/ARN para alb-standin y tofu output.
output "function_name" {
  value = aws_lambda_function.gold_api.function_name
}

output "function_arn" {
  value = aws_lambda_function.gold_api.arn
}

output "invoke_arn" {
  value = aws_lambda_function.gold_api.invoke_arn
}
