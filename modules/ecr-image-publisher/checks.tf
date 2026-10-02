data "aws_iam_principal_policy_simulation" "can_publish" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.this]
  policy_source_arn = aws_iam_role.this.arn
  action_names      = local.image_publish_actions
  resource_arns     = [var.repository_arn]
}

data "aws_iam_principal_policy_simulation" "can_authenticate" {
  count = var.boundary_checks_enabled ? 1 : 0

  depends_on        = [aws_iam_role_policy.this]
  policy_source_arn = aws_iam_role.this.arn
  action_names      = ["ecr:GetAuthorizationToken"]
}
