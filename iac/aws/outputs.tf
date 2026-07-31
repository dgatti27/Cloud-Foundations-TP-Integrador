output "bucket_name" {
  description = "Nombre del bucket que la app va a usar."
  value       = aws_s3_bucket.app.id
}

output "bucket_arn" {
  description = "ARN del bucket — útil para bucket policies o IAM."
  value       = aws_s3_bucket.app.arn
}

output "endpoint" {
  description = "Endpoint S3 efectivo (LocalStack o AWS real)."
  value       = var.localstack_endpoint
}

output "seed_object_url" {
  description = "URL del objeto seed creado por IaC."
  value       = "s3://${aws_s3_bucket.app.id}/${aws_s3_object.hello.key}"
}
