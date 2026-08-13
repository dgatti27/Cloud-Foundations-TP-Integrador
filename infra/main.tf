# =============================================================================
# Root module TP — instancia los módulos (única fuente IaC del proyecto)
# -----------------------------------------------------------------------------
# Grafo: IAM ∥ VPC ∥ S3 ∥ CloudWatch
#          └→ RDS (subnets + SG) → Secrets (host RDS) → seed SQL
#          └→ Lambda (role + opcional VPC)
#          └→ ECS/EFS (API real o stand-in Hobby)
#          └→ FinOps inventario (Budget AWS solo si create_budget)
#
# Idempotencia: tofu apply N veces → sin recrear si el state coincide.
# Un solo state: no corras otros árboles IaC en paralelo (chocan names).
# =============================================================================

resource "random_password" "master" {
  length  = 20
  special = false
}

resource "random_password" "etl" {
  length  = 20
  special = false
}

resource "random_password" "api" {
  length  = 20
  special = false
}

module "iam" {
  source = "./modules/iam"

  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
  tags         = local.common_tags
}

module "vpc" {
  source = "./modules/vpc"

  providers = {
    aws = aws.localstack
  }

  project_name = var.project_name
  region       = var.region
  vpc_cidr     = var.vpc_cidr
  enable_nat   = var.enable_nat
  tags         = local.common_tags
}

module "s3" {
  source = "./modules/s3"

  providers = {
    aws = aws.minio
  }

  bucket_names = var.lake_buckets
  tags         = local.common_tags
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  providers = {
    aws = aws.localstack
  }

  tags = local.common_tags
}

module "rds" {
  source = "./modules/rds"

  providers = {
    aws = aws.ministack
  }

  identifier             = var.db_identifier
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  db_name                = var.db_name
  master_username        = var.db_master_username
  master_password        = random_password.master.result
  subnet_ids             = module.vpc.rds_subnet_ids
  vpc_security_group_ids = [module.vpc.security_groups.rds]
  tags                   = local.common_tags
}

# Host en secrets: el address MiniStack (red Docker). Apps Compose usan overrides.
locals {
  rds_host_for_secrets = coalesce(module.rds.address, var.rds_host_override)
}

module "secrets" {
  source = "./modules/secrets"

  providers = {
    aws = aws.ministack
  }

  tags            = local.common_tags
  db_name         = var.db_name
  db_port         = 5432
  master_username = var.db_master_username
  master_password = random_password.master.result
  etl_password    = random_password.etl.result
  api_password    = random_password.api.result
  rds_host        = local.rds_host_for_secrets

  origen_demo = {
    host     = "postgres-bronce"
    port     = 5432
    dbname   = "bronce"
    username = "postgres"
    password = "postgres"
  }

  erp = {
    host     = "postgres-erp"
    port     = 5432
    dbname   = "erp"
    username = "postgres"
    password = "postgres"
  }

  depends_on = [module.rds]
}

# Seed schemas/roles + ALTER passwords (idempotente). Requiere Docker + MiniStack RDS.
resource "null_resource" "rds_seed" {
  count = var.apply_rds_seed ? 1 : 0

  triggers = {
    db_id         = module.rds.db_instance_id
    master_hash   = sha256(random_password.master.result)
    etl_hash      = sha256(random_password.etl.result)
    api_hash      = sha256(random_password.api.result)
    seed_checksum = filesha256("${local.repo_root_abs}/data/rds/seed_tp.sql")
  }

  provisioner "local-exec" {
    working_dir = path.root
    environment = {
      POST_RDS_MASTER_PASSWORD = random_password.master.result
      POST_RDS_ETL_PASSWORD    = random_password.etl.result
      POST_RDS_API_PASSWORD    = random_password.api.result
      POST_RDS_SEED            = "${replace(local.repo_root_abs, "\\", "/")}/data/rds/seed_tp.sql"
      POST_RDS_IDENTIFIER      = var.db_identifier
      POST_RDS_MASTER_USER     = var.db_master_username
      POST_RDS_DBNAME          = var.db_name
    }
    command = "python -u scripts/post_rds.py"
  }

  depends_on = [module.rds, module.secrets]
}

module "lambda_api" {
  source = "./modules/lambda"

  providers = {
    aws = aws.localstack
  }

  function_name     = var.lambda_function_name
  role_arn          = module.iam.api_role_arn
  subnet_ids        = module.vpc.compute_subnet_ids
  security_group_ids = [module.vpc.security_groups.api]
  lambda_source_dir = "${local.repo_root_abs}/apps/api"
  rds_host_override = var.rds_host_override
  rds_port_override = var.rds_port_override
  attach_vpc        = false
  tags              = local.common_tags

  depends_on = [module.cloudwatch, module.secrets]
}

module "ecs" {
  source = "./modules/ecs"

  providers = {
    aws = aws.localstack
  }

  enable_ecs_api       = var.enable_ecs_api
  repo_root            = local.repo_root_abs
  sg_efs_id            = module.vpc.security_groups.efs
  subnet_ids           = module.vpc.compute_subnet_ids
  execution_role_arn   = module.iam.ecs_execution_role_arn
  task_role_arn        = module.iam.app_role_arn
  tags                 = local.common_tags
}

module "finops" {
  source = "./modules/finops"

  providers = {
    aws = aws.localstack
  }

  create_budget = var.create_budget
  notify_email  = var.finops_notify_email
  tags          = local.common_tags
}

# Inventario VPC (mismo shape que vpc_config.json de referencia)
resource "local_file" "vpc_config" {
  filename = "${path.root}/generated/vpc_config.json"
  content = jsonencode({
    vpc_id = module.vpc.vpc_id
    region = var.region
    subnets = module.vpc.subnets
    security_groups = module.vpc.security_groups
    nat         = module.vpc.nat_gateway_id
    endpoint_s3 = module.vpc.endpoint_s3_id
    notes       = "Generado por OpenTofu. EFS/ECS API = enable_ecs_api; Hobby usa stand-in."
  })
}

resource "local_file" "vpc_config_labs" {
  filename = "${local.repo_root_abs}/labs/vpc/vpc_config.json"
  content  = local_file.vpc_config.content
}
