# Outputs RDS — address/endpoint alimentan secrets y post_rds.
output "db_instance_id" {
  value = aws_db_instance.dw.id
}

output "address" {
  value = aws_db_instance.dw.address # host Docker / DNS MiniStack
}

output "port" {
  value = aws_db_instance.dw.port
}

output "endpoint" {
  value = aws_db_instance.dw.endpoint # host:port
}

output "subnet_group_name" {
  value = aws_db_subnet_group.tp.name
}
