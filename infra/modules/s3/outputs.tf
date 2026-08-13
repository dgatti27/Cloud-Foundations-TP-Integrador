output "bucket_ids" {
  value = { for k, b in aws_s3_bucket.lake : k => b.id }
}

output "bucket_arns" {
  value = { for k, b in aws_s3_bucket.lake : k => b.arn }
}
