output "id" {
  description = "Bucket name / id."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Bucket regional domain name."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the bucket's created CMK (create_kms), else null. Wire into an aws_kms_key_policy to grant concrete principals, or reference for SSE-KMS-pinned writes."
  value       = one(aws_kms_key.this[*].arn)
}

output "kms_key_id" {
  description = "Key id of the bucket's created CMK (create_kms), else null. Use as the aws_kms_key_policy key_id."
  value       = one(aws_kms_key.this[*].key_id)
}
