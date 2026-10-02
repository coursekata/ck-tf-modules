output "stage_role_arn" {
  description = "ARN of the pull-request role that may publish candidates and inspect releases."
  value       = aws_iam_role.stage.arn
}

output "publish_role_arn" {
  description = "ARN of the branch-only role that may read candidates and publish releases."
  value       = aws_iam_role.publish.arn
}

output "candidate_repository_arn" {
  description = "Candidate repository ARN used to scope the pull-request write boundary."
  value       = var.candidate_repository_arn
}

output "release_repository_arn" {
  description = "Release repository ARN used to scope the promotion write boundary."
  value       = var.release_repository_arn
}

locals {
  stage_write_release_results     = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.stage_cannot_write_releases[0].results : []
  publish_write_candidate_results = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.publish_cannot_write_candidates[0].results : []
  stage_write_candidate_results   = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.stage_can_write_candidates[0].results : []
  publish_write_release_results   = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.publish_can_write_releases[0].results : []
  stage_read_release_results      = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.stage_can_read_releases[0].results : []
  publish_read_candidate_results  = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.publish_can_read_candidates[0].results : []
  stage_auth_results              = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.stage_can_authenticate[0].results : []
  publish_auth_results            = var.boundary_checks_enabled ? data.aws_iam_principal_policy_simulation.publish_can_authenticate[0].results : []

  stage_write_release_results_complete = (
    length(local.stage_write_release_results) == length(local.image_mutate_actions) &&
    length(setsubtract(toset(local.image_mutate_actions), toset([for result in local.stage_write_release_results : result.action_name]))) == 0
  )
  publish_write_candidate_results_complete = (
    length(local.publish_write_candidate_results) == length(local.image_mutate_actions) &&
    length(setsubtract(toset(local.image_mutate_actions), toset([for result in local.publish_write_candidate_results : result.action_name]))) == 0
  )
  stage_write_candidate_results_complete = (
    length(local.stage_write_candidate_results) == length(local.image_write_actions) &&
    length(setsubtract(toset(local.image_write_actions), toset([for result in local.stage_write_candidate_results : result.action_name]))) == 0
  )
  publish_write_release_results_complete = (
    length(local.publish_write_release_results) == length(local.image_write_actions) &&
    length(setsubtract(toset(local.image_write_actions), toset([for result in local.publish_write_release_results : result.action_name]))) == 0
  )
  stage_read_release_results_complete = (
    length(local.stage_read_release_results) == 1 &&
    try(one(local.stage_read_release_results).action_name == "ecr:DescribeImages", false)
  )
  publish_read_candidate_results_complete = (
    length(local.publish_read_candidate_results) == length(local.image_read_actions) &&
    length(setsubtract(toset(local.image_read_actions), toset([for result in local.publish_read_candidate_results : result.action_name]))) == 0
  )
  stage_auth_results_complete = (
    length(local.stage_auth_results) == 1 &&
    try(one(local.stage_auth_results).action_name == "ecr:GetAuthorizationToken", false)
  )
  publish_auth_results_complete = (
    length(local.publish_auth_results) == 1 &&
    try(one(local.publish_auth_results).action_name == "ecr:GetAuthorizationToken", false)
  )
}

output "boundary_simulation" {
  description = "Live IAM simulator verdicts for the candidate and release boundary. Null when checks are disabled."
  value = var.boundary_checks_enabled ? {
    stage_can_write_releases     = anytrue([for result in local.stage_write_release_results : result.allowed])
    publish_can_write_candidates = anytrue([for result in local.publish_write_candidate_results : result.allowed])
    stage_can_write_candidates   = alltrue([for result in local.stage_write_candidate_results : result.allowed])
    publish_can_write_releases   = alltrue([for result in local.publish_write_release_results : result.allowed])
    stage_can_read_releases      = alltrue([for result in local.stage_read_release_results : result.allowed])
    publish_can_read_candidates  = alltrue([for result in local.publish_read_candidate_results : result.allowed])
    stage_can_authenticate       = alltrue([for result in local.stage_auth_results : result.allowed])
    publish_can_authenticate     = alltrue([for result in local.publish_auth_results : result.allowed])
  } : null

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.stage_write_release_results_complete &&
      !anytrue([for result in local.stage_write_release_results : result.allowed])
    ) : true
    error_message = "the pull-request image role can write the release repository or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.publish_write_candidate_results_complete &&
      !anytrue([for result in local.publish_write_candidate_results : result.allowed])
    ) : true
    error_message = "the promotion image role can write the candidate repository or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.stage_write_candidate_results_complete &&
      alltrue([for result in local.stage_write_candidate_results : result.allowed])
    ) : true
    error_message = "the pull-request image role cannot complete the candidate image workflow or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.publish_write_release_results_complete &&
      alltrue([for result in local.publish_write_release_results : result.allowed])
    ) : true
    error_message = "the promotion image role cannot complete the release image workflow or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.stage_read_release_results_complete &&
      alltrue([for result in local.stage_read_release_results : result.allowed])
    ) : true
    error_message = "the pull-request image role cannot inspect the release repository or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.publish_read_candidate_results_complete &&
      alltrue([for result in local.publish_read_candidate_results : result.allowed])
    ) : true
    error_message = "the promotion image role cannot read the candidate repository or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.stage_auth_results_complete &&
      alltrue([for result in local.stage_auth_results : result.allowed])
    ) : true
    error_message = "the pull-request image role cannot authenticate to ECR or its IAM simulation was incomplete."
  }

  precondition {
    condition = var.boundary_checks_enabled ? (
      local.publish_auth_results_complete &&
      alltrue([for result in local.publish_auth_results : result.allowed])
    ) : true
    error_message = "the promotion image role cannot authenticate to ECR or its IAM simulation was incomplete."
  }
}
