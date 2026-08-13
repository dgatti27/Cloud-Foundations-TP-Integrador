# =============================================================================
# outputs.tf — Valores que imprime `tofu apply` / `tofu output`
# -----------------------------------------------------------------------------
# Sirven para copiar a scripts, documentar el entregable o encadenar demos.
# No crean infra: solo exponen atributos del state.
# =============================================================================

# Mapa nombre → id (en S3 el id suele ser el propio nombre del bucket)
output "bucket_ids" {
  description = "IDs/nombres de los buckets del lake creados por este stack"
  value       = { for k, b in aws_s3_bucket.lake : k => b.id }
}

# ARNs arn:aws:s3:::nombre — útiles al escribir policies IAM en AWS real
output "bucket_arns" {
  description = "ARNs de los buckets (referencia para policies / docs)"
  value       = { for k, b in aws_s3_bucket.lake : k => b.arn }
}

# Recuerda contra qué endpoint se aplicó (MinIO local vs otro)
output "minio_endpoint" {
  description = "Endpoint S3 usado por el provider de este stack"
  value       = var.minio_endpoint
}

# null si no se subió seed; si no, URI s3://bucket/key
output "seed_object" {
  description = "URI del README semilla, o null si upload_seed_object=false"
  value = try(
    "s3://${aws_s3_object.seed_readme[0].bucket}/${aws_s3_object.seed_readme[0].key}",
    null
  )
}

# Texto de ayuda post-apply (no es un recurso; solo DX del lab)
output "next_steps" {
  description = "Qué correr después del apply (demos Python)"
  value       = <<-EOT
    Infra lake OK en MinIO.
    Demos (versioning mutate, AssumeRole STS, presign):
      python s3/s3_demo.py --skip-infra
    Listar:
      aws --endpoint-url ${var.minio_endpoint} s3 ls
  EOT
}
