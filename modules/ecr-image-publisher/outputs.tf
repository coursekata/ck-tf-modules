output "role_arn" {
  description = "ARN of the protected-branch role that may publish images."
  value       = aws_iam_role.this.arn
}

output "repository_arn" {
  description = "Repository ARN used to scope the publishing role."
  value       = var.repository_arn
}

locals {
  publish_results = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.can_publish[0].results : []
  auth_results    = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.can_authenticate[0].results : []

  publish_results_complete = (
    length(local.publish_results) == length(local.image_publish_actions) &&
    length(setsubtract(toset(local.image_publish_actions), toset([for result in local.publish_results : result.action_name]))) == 0
  )
  auth_results_complete = (
    length(local.auth_results) == 1 &&
    try(one(local.auth_results).action_name == "ecr:GetAuthorizationToken", false)
  )
}

output "boundary_simulation" {
  description = "Live IAM simulator verdicts for the publishing role. Null when checks are disabled."
  value = var.boundary_checks_enabled ? {
    can_publish      = alltrue([for result in local.publish_results : result.allowed])
    can_authenticate = alltrue([for result in local.auth_results : result.allowed])
  } : null

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.publish_results_complete &&
      alltrue([for result in local.publish_results : result.allowed])
    ) : true
    error_message = "the image publishing role cannot complete the ECR publish workflow or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.auth_results_complete &&
      alltrue([for result in local.auth_results : result.allowed])
    ) : true
    error_message = "the image publishing role cannot authenticate to ECR or its IAM simulation was incomplete."
  }
}
