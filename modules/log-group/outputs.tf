output "arn" {
  description = "ARN of the log group (no trailing :*). CloudTrail's cloud_watch_logs_group_arn wants the arn with a ':*' suffix — append it at the call site."
  value       = aws_cloudwatch_log_group.this.arn
}

output "name" {
  description = "Name of the log group (the prefix + rendered id)."
  value       = aws_cloudwatch_log_group.this.name
}
