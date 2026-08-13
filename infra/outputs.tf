output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_config_path" {
  value = local_file.vpc_config.filename
}

output "security_groups" {
  value = module.vpc.security_groups
}

output "subnets" {
  value = module.vpc.subnets
}

output "lake_buckets" {
  value = module.s3.bucket_ids
}

output "db_endpoint" {
  value = module.rds.endpoint
}

output "db_address" {
  value = module.rds.address
}

output "secret_names" {
  value = module.secrets.secret_names
}

output "lambda_function" {
  value = module.lambda_api.function_name
}

output "iam_roles" {
  value = {
    app           = module.iam.app_role_arn
    api           = module.iam.api_role_arn
    ecs_execution = module.iam.ecs_execution_role_arn
    db            = module.iam.db_role_arn
  }
}

output "ecs_mode" {
  value = module.ecs.mode
}

output "cloudwatch_log_groups" {
  value = module.cloudwatch.log_group_names
}

output "endpoints" {
  value = {
    localstack = var.localstack_endpoint
    ministack  = var.ministack_endpoint
    minio      = var.minio_endpoint
  }
}
