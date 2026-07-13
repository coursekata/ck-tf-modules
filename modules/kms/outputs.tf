output "key_arn" {
  description = "The CMK ARN. Wire into aws_sns_topic.kms_master_key_id, an s3-bucket kms_key_arn, a CodePipeline encryption_key, etc."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "The CMK key id."
  value       = aws_kms_key.this.key_id
}

output "alias_arn" {
  description = "The key alias ARN."
  value       = aws_kms_alias.this.arn
}

output "alias_name" {
  description = "The key alias name (alias/<rendered-id>)."
  value       = aws_kms_alias.this.name
}
