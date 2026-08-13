# =============================================================================
# outputs.tf — Valores de `tofu apply` / `tofu output`
# -----------------------------------------------------------------------------
# No crean infra: exponen IDs del state para entregable, scripts y demos.
# =============================================================================

output "vpc_id" {
  description = "ID de la VPC tag Name=tp-integrador-vpc"
  value       = aws_vpc.main.id
}

output "subnets" {
  description = "Subnet IDs por rol (public / rds / compute × AZ a|b)"
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
  description = "SG IDs (GroupName tp-*; tag Name = sg-alb|api|ecs-etl|rds|efs)"
  value = {
    alb     = aws_security_group.alb.id
    api     = aws_security_group.api.id
    ecs_etl = aws_security_group.ecs_etl.id
    rds     = aws_security_group.rds.id
    efs     = aws_security_group.efs.id
  }
}

output "route_tables" {
  description = "RTs: pública (IGW), RDS (sin Internet), compute (NAT + vpce)"
  value = {
    public  = aws_route_table.public.id
    rds     = aws_route_table.rds.id
    compute = aws_route_table.compute.id
  }
}

output "igw_id" {
  description = "Internet Gateway (entrada ALB + base del NAT)"
  value       = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
  description = "NAT ETL; null si enable_nat=false"
  value       = try(aws_nat_gateway.main[0].id, null)
}

output "endpoint_s3_id" {
  description = "VPC endpoint Gateway S3 (modelo AWS; lake local = MinIO, no este vpce)"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_config_path" {
  description = "Path del JSON inventario si write_vpc_config=true"
  value       = var.write_vpc_config ? "${path.module}/../vpc_config.json" : null
}

output "next_steps" {
  description = "Ayuda post-apply (DX del lab)"
  value       = <<-EOT
    VPC lab-07-v2 OK en LocalStack.
    Inventario: vpc/vpc_config.json
    Inspección: awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=tp-integrador-vpc"
    Bash alternativo (sin OpenTofu): bash vpc/provision_vpc_v2.sh
    Labs siguientes: rds/, lambda/, ecs/ leen vpc_config.json
  EOT
}
