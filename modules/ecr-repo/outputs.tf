output "repository_url" {
  description = "ECR repository URL (`{registry}/{repo}`). Append `@sha256:{digest}` on the consumer side to pin the task definition."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "ECR repository name. Pass to `data.aws_ecr_image` on the consumer side to resolve a content tag to its digest."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "ECR repository ARN. Scope the CI push identity's ECR permissions to this."
  value       = aws_ecr_repository.this.arn
}
