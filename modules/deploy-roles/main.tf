# Reusable spoke DEPLOY ROLES for the OIDC hub-spoke delivery model. Creates the IAM roles a
# spoke's CI assumes (via the hub) to plan/apply its OWN infrastructure:
#   - apply (RW): assumable ONLY by the hub CI APPLY role, which is itself reachable only from
#     the spoke's protected GitHub Environment -> the gated write path.
#   - plan  (RO, optional): assumable ONLY by the hub CI PLAN role (PR runs) -> the read path
#     for PR plan previews. Omit (hub_plan_role_arn = null) for an apply-only spoke.
#
# The standardized, security-critical part is the TRUST: each role trusts EXACTLY one hub role
# ARN (no wildcard) for sts:AssumeRole + sts:TagSession. The spoke supplies its own permissions.
# Names/tags come from the cloudposse/context provider configured by the consuming root — which
# must declare the `attributes` property so the plan role can render <...>-plan.

locals {
  create_plan = var.hub_plan_role_arn != null
}

# Role names: apply = <namespace>-<tenant>-<name> (e.g. ck-org-deploy); plan = <...>-<name>-plan.
data "context_label" "apply" {
  properties = ["namespace", "tenant", "name"]
  values     = { name = var.name }
}

data "context_tags" "apply" {
  values = { name = var.name }
}

data "context_label" "plan" {
  count = local.create_plan ? 1 : 0

  properties = ["namespace", "tenant", "name", "attributes"]
  values     = { name = var.name, attributes = "plan" }
}

data "context_tags" "plan" {
  count = local.create_plan ? 1 : 0

  values = { name = var.name, attributes = "plan" }
}

# --- trust: each deploy role trusts EXACTLY its hub CI role (a regular IAM principal that
# itself entered via OIDC). sts:TagSession because configure-aws-credentials tags sessions.
# The hub CI role need not exist when these roles are created (IAM validates the principal ARN
# syntactically, not existentially) — but the hub apply must land before an assume succeeds. ---
data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [var.hub_apply_role_arn]
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
  name               = data.context_label.apply.rendered
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
  tags               = merge(data.context_tags.apply.tags, { Name = data.context_label.apply.rendered })

  lifecycle {
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

  name               = data.context_label.plan[0].rendered
  assume_role_policy = data.aws_iam_policy_document.plan_trust[0].json
  tags               = merge(data.context_tags.plan[0].tags, { Name = data.context_label.plan[0].rendered })

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
