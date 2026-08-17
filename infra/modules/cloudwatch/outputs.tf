# Outputs CloudWatch — nombres de log groups creados.
output "log_group_names" {
  value = {
    ecs_airflow = aws_cloudwatch_log_group.ecs_airflow.name
    lambda_api  = aws_cloudwatch_log_group.lambda_api.name
    etl         = aws_cloudwatch_log_group.etl.name
  }
}
