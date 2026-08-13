# =============================================================================
# outputs.tf — Valores de `tofu apply` / `tofu output`
# -----------------------------------------------------------------------------
# No crean infra: exponen IDs/endpoints para demos y labs siguientes.
# =============================================================================

output "vpc_id" {
  description = "VPC resuelta en LocalStack (lab 07-v2)"
  value       = data.aws_vpc.tp.id
}

output "rds_subnet_ids" {
  description = "Subnets Role=rds usadas en el DB subnet group"
  value       = data.aws_subnets.rds.ids
}

output "sg_rds_id" {
  description = "Security group sg-rds (reusado, no creado acá)"
  value       = data.aws_security_groups.rds.ids[0]
}

output "db_subnet_group_name" {
  description = "Nombre del DB subnet group Multi-AZ"
  value       = aws_db_subnet_group.tp.name
}

output "db_instance_id" {
  description = "Identifier de la instancia (tp-dw-db)"
  value       = aws_db_instance.dw.id
}

output "db_address" {
  description = "Hostname MiniStack de la instancia"
  value       = aws_db_instance.dw.address
}

output "db_endpoint" {
  description = "host:port de la instancia"
  value       = aws_db_instance.dw.endpoint
}

output "db_port" {
  description = "Puerto Postgres"
  value       = aws_db_instance.dw.port
}

output "secret_names" {
  description = "Nombres de secrets en MiniStack"
  value = {
    master = aws_secretsmanager_secret.master.name
    etl    = aws_secretsmanager_secret.etl.name
    api    = aws_secretsmanager_secret.api.name
  }
}

output "snapshot_bucket" {
  description = "Bucket MinIO de dumps, o null si manage_snapshot_bucket=false"
  value       = try(aws_s3_bucket.snapshot[0].id, null)
}

output "ministack_endpoint" {
  description = "Endpoint MiniStack usado por este stack"
  value       = var.ministack_endpoint
}

output "next_steps" {
  description = "Ayuda post-apply (DX del lab)"
  value       = <<-EOT
    Infra RDS OK en MiniStack (+ secrets; seed=${var.apply_rds_seed}).
    Demos (verify privilegios + snapshot/dump MinIO):
      python rds/rds_tp_demo.py --skip-infra
    Verificar:
      aws --endpoint-url ${var.ministack_endpoint} rds describe-db-instances --db-instance-identifier ${var.db_identifier}
      aws --endpoint-url ${var.ministack_endpoint} secretsmanager list-secrets
  EOT
}
