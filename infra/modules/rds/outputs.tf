output "db_instance_id" {
  value = aws_db_instance.dw.id
}

output "address" {
  value = aws_db_instance.dw.address
}

output "port" {
  value = aws_db_instance.dw.port
}

output "endpoint" {
  value = aws_db_instance.dw.endpoint
}

output "subnet_group_name" {
  value = aws_db_subnet_group.tp.name
}
