# Outputs del módulo VPC — IDs que consumen rds / lambda / ecs / root.
output "vpc_id" { value = aws_vpc.main.id }

output "subnets" {
  value = {
    public_a  = aws_subnet.public_a.id
    public_b  = aws_subnet.public_b.id
    rds_a     = aws_subnet.rds_a.id
    rds_b     = aws_subnet.rds_b.id
    compute_a = aws_subnet.compute_a.id
    compute_b = aws_subnet.compute_b.id
  }
}

output "security_groups" {
  value = {
    alb     = aws_security_group.alb.id
    api     = aws_security_group.api.id
    ecs_etl = aws_security_group.ecs_etl.id
    rds     = aws_security_group.rds.id
    efs     = aws_security_group.efs.id
  }
}

output "nat_gateway_id" {
  value = try(aws_nat_gateway.main[0].id, null) # null si enable_nat=false
}

output "endpoint_s3_id" {
  value = aws_vpc_endpoint.s3.id
}

output "rds_subnet_ids" {
  value = [aws_subnet.rds_a.id, aws_subnet.rds_b.id]
}

output "compute_subnet_ids" {
  value = [aws_subnet.compute_a.id, aws_subnet.compute_b.id]
}
