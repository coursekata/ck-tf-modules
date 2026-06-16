output "bucket_name" {
  description = "Name (and id) of the state bucket. Wire into a consuming root's backend.tf `bucket`."
  value       = aws_s3_bucket.tfstate.id
}

output "bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.tfstate.arn
}
