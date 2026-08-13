variable "project_name" { type = string }
variable "region" { type = string }
variable "vpc_cidr" { type = string }
variable "enable_nat" { type = bool }
variable "tags" { type = map(string) }

locals {
  az_a = "${var.region}a"
  az_b = "${var.region}b"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "tp-integrador-vpc"
    Lab  = "07-v2"
  })
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1) # 10.0.1.0/24
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags = merge(var.tags, { Name = "public-alb-a", Tier = "public", Role = "alb" })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
  tags = merge(var.tags, { Name = "public-alb-b", Tier = "public", Role = "alb" })
}

resource "aws_subnet" "rds_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10)
  availability_zone = local.az_a
  tags              = merge(var.tags, { Name = "private-rds-a", Tier = "private", Role = "rds" })
}

resource "aws_subnet" "rds_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11)
  availability_zone = local.az_b
  tags              = merge(var.tags, { Name = "private-rds-b", Tier = "private", Role = "rds" })
}

resource "aws_subnet" "compute_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 20)
  availability_zone = local.az_a
  tags              = merge(var.tags, { Name = "private-compute-a", Tier = "private", Role = "ecs-lambda-efs" })
}

resource "aws_subnet" "compute_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 21)
  availability_zone = local.az_b
  tags              = merge(var.tags, { Name = "private-compute-b", Tier = "private", Role = "ecs-lambda-efs" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "tp-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "rt-public-alb" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "rds" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "rt-private-rds" })
}

resource "aws_route_table_association" "rds_a" {
  subnet_id      = aws_subnet.rds_a.id
  route_table_id = aws_route_table.rds.id
}

resource "aws_route_table_association" "rds_b" {
  subnet_id      = aws_subnet.rds_b.id
  route_table_id = aws_route_table.rds.id
}

resource "aws_route_table" "compute" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "rt-private-compute" })
}

resource "aws_route_table_association" "compute_a" {
  subnet_id      = aws_subnet.compute_a.id
  route_table_id = aws_route_table.compute.id
}

resource "aws_route_table_association" "compute_b" {
  subnet_id      = aws_subnet.compute_b.id
  route_table_id = aws_route_table.compute.id
}

resource "aws_eip" "nat" {
  count  = var.enable_nat ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "tp-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_a.id
  tags          = merge(var.tags, { Name = "tp-nat-etl" })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route" "compute_nat" {
  count                  = var.enable_nat ? 1 : 0
  route_table_id         = aws_route_table.compute.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

# ── Security groups (reglas en recursos separados → sin ciclos) ──────────────

# AWS no permite GroupName que empiece con "sg-" (reservado a IDs).
# El tag Name=sg-* mantiene el lookup de los demos (filter tag:Name).
resource "aws_security_group" "alb" {
  name        = "tp-alb"
  description = "ALB HTTPS"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "sg-alb" })
}

resource "aws_security_group" "api" {
  name        = "tp-api"
  description = "Lambda API"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "sg-api" })
}

resource "aws_security_group" "ecs_etl" {
  name        = "tp-ecs-etl"
  description = "ECS ETL"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "sg-ecs-etl" })
}

resource "aws_security_group" "rds" {
  name        = "tp-rds"
  description = "RDS"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "sg-rds" })
}

resource "aws_security_group" "efs" {
  name        = "tp-efs"
  description = "EFS"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "sg-efs" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.api.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "ALB"

  # LocalStack a veces refresca como "000000000000/sg-…"; evita drift eterno.
  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_api" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.api.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "API"

  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ecs_etl.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "ETL"

  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_ecs" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.ecs_etl.id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  description                  = "ETL"

  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.compute.id, aws_route_table.rds.id]
  tags              = merge(var.tags, { Name = "vpce-s3-datalake" })
}
