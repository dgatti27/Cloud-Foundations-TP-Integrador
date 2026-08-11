output "bucket_ids" {
  description = "IDs/nombres de los buckets del lake"
  value       = { for k, b in aws_s3_bucket.lake : k => b.id }
}

output "bucket_arns" {
  description = "ARNs s3:// (útiles en AWS real / policies)"
  value       = { for k, b in aws_s3_bucket.lake : k => b.arn }
}

output "minio_endpoint" {
  description = "Endpoint S3 usado por este stack"
  value       = var.minio_endpoint
}

output "seed_object" {
  description = "Objeto semilla si upload_seed_object=true"
  value = try(
    "s3://${aws_s3_object.seed_readme[0].bucket}/${aws_s3_object.seed_readme[0].key}",
    null
  )
}

output "next_steps" {
  description = "Qué sigue después del apply"
  value       = <<-EOT
    Infra lake OK en MinIO.
    Demos (versioning mutate, AssumeRole STS, presign):
      python s3/s3_demo.py --skip-infra
    Listar:
      aws --endpoint-url ${var.minio_endpoint} s3 ls
  EOT
}
