# =============================================================================
# outputs.tf — Valores que imprime `tofu apply` / `tofu output`
# -----------------------------------------------------------------------------
# Sirven para copiar a demos, documentar el entregable o armar assume-role.
# No crean infra: solo exponen atributos del state.
# =============================================================================

# Nombres de grupos (bi-ops / bi-admin) — útiles para get-group / docs
output "group_names" {
  description = "Grupos IAM creados (bi-ops / bi-admin)"
  value       = { for k, g in aws_iam_group.lab : k => g.name }
}

# ARNs tipo arn:aws:iam::000000000000:policy/S3RWTP (cuenta LocalStack Hobby)
output "policy_arns" {
  description = "ARNs de policies administradas adjuntadas a cada grupo"
  value       = { for k, p in aws_iam_policy.managed : k => p.arn }
}

# Mapa usuario → grupo (mismo local que main.tf)
output "user_names" {
  description = "Usuarios IAM y su grupo"
  value       = local.users
}

# ARNs para: awslocal sts assume-role --role-arn ...
output "role_arns" {
  description = "ARNs de app-role / db-role (para sts assume-role)"
  value       = { for k, r in aws_iam_role.lab : k => r.arn }
}

# Vacío {} si manage_minio_buckets=false
output "raw_bucket_ids" {
  description = "Buckets MinIO creados por este stack (vacío si manage_minio_buckets=false)"
  value       = { for k, b in aws_s3_bucket.raw : k => b.id }
}

output "localstack_endpoint" {
  description = "Endpoint LocalStack usado para IAM"
  value       = var.localstack_endpoint
}

output "minio_endpoint" {
  description = "Endpoint MinIO usado para buckets raw"
  value       = var.minio_endpoint
}

# Texto de ayuda post-apply (DX del lab; no es un recurso)
output "next_steps" {
  description = "Qué correr después del apply (demos Python / verificación CLI)"
  value       = <<-EOT
    Infra IAM OK en LocalStack (+ buckets raw en MinIO si manage_minio_buckets=true).
    Demos (access key larga + AssumeRole STS + list MinIO):
      python iam/iam_demo.py --skip-infra
    Verificar:
      awslocal iam list-roles
      awslocal iam get-group --group-name bi-admin
      aws --endpoint-url ${var.minio_endpoint} s3 ls
  EOT
}
