data "aws_iam_principal_policy_simulation" "stage_cannot_write_releases" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.stage]
  policy_source_arn = aws_iam_role.stage.arn
  action_names      = local.image_mutate_actions
  resource_arns     = [var.release_repository_arn]

}

data "aws_iam_principal_policy_simulation" "publish_cannot_write_candidates" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.publish]
  policy_source_arn = aws_iam_role.publish.arn
  action_names      = local.image_mutate_actions
  resource_arns     = [var.candidate_repository_arn]

}

data "aws_iam_principal_policy_simulation" "stage_can_write_candidates" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.stage]
  policy_source_arn = aws_iam_role.stage.arn
  action_names      = local.image_write_actions
  resource_arns     = [var.candidate_repository_arn]

}

data "aws_iam_principal_policy_simulation" "publish_can_write_releases" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.publish]
  policy_source_arn = aws_iam_role.publish.arn
  action_names      = local.image_write_actions
  resource_arns     = [var.release_repository_arn]

}

data "aws_iam_principal_policy_simulation" "stage_can_read_releases" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.stage]
  policy_source_arn = aws_iam_role.stage.arn
  action_names      = ["ecr:DescribeImages"]
  resource_arns     = [var.release_repository_arn]

}

data "aws_iam_principal_policy_simulation" "publish_can_read_candidates" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.publish]
  policy_source_arn = aws_iam_role.publish.arn
  action_names      = local.image_read_actions
  resource_arns     = [var.candidate_repository_arn]

}

data "aws_iam_principal_policy_simulation" "stage_can_authenticate" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.stage]
  policy_source_arn = aws_iam_role.stage.arn
  action_names      = ["ecr:GetAuthorizationToken"]

}

data "aws_iam_principal_policy_simulation" "publish_can_authenticate" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.publish]
  policy_source_arn = aws_iam_role.publish.arn
  action_names      = ["ecr:GetAuthorizationToken"]

}
