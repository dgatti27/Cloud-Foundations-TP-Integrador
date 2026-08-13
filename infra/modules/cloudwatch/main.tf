variable "tags" { type = map(string) }

resource "aws_cloudwatch_log_group" "ecs_airflow" {
  name              = "/ecs/tp-airflow"
  retention_in_days = 7
  tags              = merge(var.tags, { Name = "tp-airflow-logs" })
}

resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/tp-gold-api"
  retention_in_days = 14
  tags              = merge(var.tags, { Name = "tp-gold-api-logs" })
}

resource "aws_cloudwatch_log_group" "etl" {
  name              = "/tp-integrador/etl"
  retention_in_days = 14
  tags              = merge(var.tags, { Name = "tp-etl-logs" })
}
