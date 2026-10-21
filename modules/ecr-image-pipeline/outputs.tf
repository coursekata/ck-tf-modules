output "repositories" {
  description = "Per image, the URLs of its candidate, release and cache repositories. The image workflow's targets input names these."
  value = {
    for image in var.images : image => {
      candidate = aws_ecr_repository.this["${image}/candidate"].repository_url
      release   = aws_ecr_repository.this["${image}/release"].repository_url
      cache     = aws_ecr_repository.cache["${image}/cache"].repository_url
    }
  }
}

output "candidate_role_arn" {
  description = "Role the image workflow's default-branch build assumes, on a push or a run by hand, to push candidates and read the release cache."
  value       = aws_iam_role.this["candidate"].arn
}

output "cache_read_role_arn" {
  description = "Role the image workflow assumes on a pull request, to read the release cache."
  value       = aws_iam_role.this["cache-read"].arn
}

output "release_role_arn" {
  description = "Role the image workflow's release job assumes in the release environment."
  value       = aws_iam_role.this["release"].arn
}

output "release_read_role_arns" {
  description = "Per consumer repository in release_readers, the role its Renovate job assumes to read the release repositories."
  value       = { for key, x in local.readers : x.repository => aws_iam_role.this[key].arn }
}
