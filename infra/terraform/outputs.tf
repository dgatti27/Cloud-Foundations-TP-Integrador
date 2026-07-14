output "project_name" {
  value = local.project_name
}

output "environment" {
  value = local.environment
}

output "bucket_raw" {
  value = aws_s3_bucket.raw.bucket
}

output "bucket_processed" {
  value = aws_s3_bucket.processed.bucket
}

output "bucket_curated" {
  value = aws_s3_bucket.curated.bucket
}

output "queue_events_url" {
  value = aws_sqs_queue.events.url
}

output "queue_events_dlq_url" {
  value = aws_sqs_queue.events_dlq.url
}
