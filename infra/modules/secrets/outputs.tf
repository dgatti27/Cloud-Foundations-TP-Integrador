output "secret_arns" {
  value = {
    master      = aws_secretsmanager_secret.master.arn
    etl         = aws_secretsmanager_secret.etl.arn
    api         = aws_secretsmanager_secret.api.arn
    origen_demo = aws_secretsmanager_secret.origen_demo.arn
    erp         = aws_secretsmanager_secret.erp.arn
  }
}

output "secret_names" {
  value = {
    master      = aws_secretsmanager_secret.master.name
    etl         = aws_secretsmanager_secret.etl.name
    api         = aws_secretsmanager_secret.api.name
    origen_demo = aws_secretsmanager_secret.origen_demo.name
    erp         = aws_secretsmanager_secret.erp.name
  }
}
