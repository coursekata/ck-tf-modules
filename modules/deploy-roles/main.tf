# Reusable spoke DEPLOY ROLES for the OIDC hub-spoke delivery model. Creates the IAM roles a
# spoke's CI assumes (via the hub) to plan/apply its OWN infrastructure:
#   - apply (RW): the gated write path. Assumable by the spoke's apply principal(s) — the hub CI
#     APPLY role (GitHub-Environment-gated), and/or additional principals for a non-GHA executor
#     (e.g. a CodeBuild apply role in the CodePipeline delivery model). At least one is required.
#   - plan  (RO, optional): assumable ONLY by the hub CI PLAN role (PR runs) -> the read path
#     for PR plan previews. Omit (hub_plan_role_arn = null) for an apply-only spoke.
#
# The standardized, security-critical part is the TRUST: every trusted principal is a concrete ARN
# (no wildcard), for sts:AssumeRole + sts:TagSession. The plan role trusts EXACTLY the hub plan role.
# The spoke supplies its own permissions. The two role names append the role type to the shared
# context render, so they are unique by construction: apply -> ck-<domain>-<name>-apply, plan ->
# ck-<domain>-<name>-plan. The suffix is a literal (not a context slot) — the role-type distinction
# isn't worth a tag; add one manually if ever needed.
locals {
  create_plan = var.hub_plan_role_arn != null
  apply_name  = "${data.context_label.this.rendered}-apply"
  plan_name   = "${data.context_label.this.rendered}-plan"

  # The apply role's trusted principals: the legacy single hub apply role (if set) plus any explicit
  # apply_principal_arns. distinct() so passing the same ARN both ways doesn't duplicate a statement.
  # A CodePipeline spoke trusts its CodeBuild apply role here and leaves hub_apply_role_arn null to
  # retire the GHA apply path (the plan role still trusts the hub plan role: GHA plans, CP applies).
  apply_trust_principals = distinct(concat(
    var.hub_apply_role_arn != null ? [var.hub_apply_role_arn] : [],
    var.apply_principal_arns,
  ))
}

# --- trust: the apply role trusts its apply principal(s); the plan role trusts its hub CI plan role
# (regular IAM principals that themselves entered via OIDC, or a CodeBuild service role).
# sts:TagSession because configure-aws-credentials tags sessions. A trusted principal need not exist
# when these roles are created (IAM validates the ARN syntactically, not existentially) — but it must
# land before an assume succeeds. ---
data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = local.apply_trust_principals
    }
  }
}

data "aws_iam_policy_document" "plan_trust" {
  count = local.create_plan ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [var.hub_plan_role_arn]
    }
  }
}

# --- apply (RW) role: the gated write path. Always created. ---
resource "aws_iam_role" "apply" {
  name               = local.apply_name
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
  tags               = merge(data.context_tags.this.tags, { Name = local.apply_name })

  lifecycle {
    precondition {
      condition     = length(local.apply_trust_principals) > 0
      error_message = "the apply role needs at least one trusted principal: set hub_apply_role_arn and/or apply_principal_arns (a trustless role can never be assumed)."
    }
    precondition {
      condition     = length(var.apply_policy_arns) > 0 || var.apply_inline_policy != null
      error_message = "the apply role needs permissions: set apply_policy_arns and/or apply_inline_policy (a permissionless deploy role fails every gated apply with AccessDenied)."
    }
  }
}

resource "aws_iam_role_policy_attachment" "apply_managed" {
  for_each = toset(var.apply_policy_arns)

  role       = aws_iam_role.apply.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "apply_inline" {
  count = var.apply_inline_policy != null ? 1 : 0

  name   = "deploy-permissions"
  role   = aws_iam_role.apply.id
  policy = var.apply_inline_policy
}

# --- plan (RO) role: PR-scoped read path. Optional — apply-only spokes omit it. ---
resource "aws_iam_role" "plan" {
  count = local.create_plan ? 1 : 0

  name               = local.plan_name
  assume_role_policy = data.aws_iam_policy_document.plan_trust[0].json
  tags               = merge(data.context_tags.this.tags, { Name = local.plan_name })

  lifecycle {
    precondition {
      condition     = length(var.plan_policy_arns) > 0 || var.plan_inline_policy != null
      error_message = "the plan role needs read permissions: set plan_policy_arns and/or plan_inline_policy."
    }
  }
}

resource "aws_iam_role_policy_attachment" "plan_managed" {
  for_each = local.create_plan ? toset(var.plan_policy_arns) : toset([])

  role       = aws_iam_role.plan[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "plan_inline" {
  count = local.create_plan && var.plan_inline_policy != null ? 1 : 0

  name   = "deploy-readonly"
  role   = aws_iam_role.plan[0].id
  policy = var.plan_inline_policy
}
