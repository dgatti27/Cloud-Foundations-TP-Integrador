# =============================================================================
# Outputs del root — lo que ves con `tofu output`
# =============================================================================
# Útiles para smoke checks, demos y scripts (ecs.py, Postman, evidencia).
# No imprimen passwords (solo names/ARNs/endpoints).
# =============================================================================

# --- Red ---
output "vpc_id" {
  description = "ID de la VPC Multi-AZ."
  value       = module.vpc.vpc_id
}

output "vpc_config_path" {
  description = "JSON inventario VPC (generated/)."
  value       = local_file.vpc_config.filename
}

output "security_groups" {
  description = "Mapa de SGs: alb, api, ecs_etl, rds, efs."
  value       = module.vpc.security_groups
}

output "subnets" {
  description = "Mapa de subnet IDs por rol (public/rds/compute)."
  value       = module.vpc.subnets
}

# --- Lake ---
output "lake_buckets" {
  description = "Buckets MinIO creados (nombre → id)."
  value       = module.s3.bucket_ids
}

# --- RDS + secrets ---
output "db_endpoint" {
  description = "Endpoint host:port de la instancia RDS."
  value       = module.rds.endpoint
}

output "db_address" {
  description = "Hostname/address MiniStack de la RDS."
  value       = module.rds.address
}

output "secret_names" {
  description = "Nombres de secrets (dw/rds-*, dw/erp, dw/origen-demo)."
  value       = module.secrets.secret_names
}

# --- Cómputo / API ---
output "lambda_function" {
  description = "Nombre de la función gold API."
  value       = module.lambda_api.function_name
}

output "iam_roles" {
  description = "ARNs de roles de servicio."
  value = {
    app           = module.iam.app_role_arn
    api           = module.iam.api_role_arn
    ecs_execution = module.iam.ecs_execution_role_arn
    db            = module.iam.db_role_arn
  }
}

output "ecs_mode" {
  description = "hobby-standin | aws-api."
  value       = module.ecs.mode
}

output "cloudwatch_log_groups" {
  description = "Nombres de log groups creados."
  value       = module.cloudwatch.log_group_names
}

# --- FinOps / endpoints emuladores ---
output "finops_inventory" {
  description = "Path del inventario FinOps JSON."
  value       = module.finops.inventory_path
}

output "endpoints" {
  description = "URLs de LocalStack / MiniStack / MinIO usadas en el apply."
  value = {
    localstack = var.localstack_endpoint
    ministack  = var.ministack_endpoint
    minio      = var.minio_endpoint
  }
}
