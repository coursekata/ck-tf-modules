# Reusable spoke DEPLOY ROLES for the OIDC hub-spoke delivery model. Creates the IAM roles a
# spoke's CI assumes (via the hub) to plan/apply its OWN infrastructure:
#   - apply (RW): the gated write path. Assumable by the spoke's apply principal(s) — the hub CI
#     APPLY role (GitHub-Environment-gated), and/or additional principals for a non-GHA executor
#     (e.g. a CodeBuild apply role in the CodePipeline delivery model). At least one is required.
#   - plan  (RO, optional): the read path. Assumable by the spoke's plan principal(s) — the hub CI
#     PLAN role (PR previews), and/or additional principals for a non-GHA executor (e.g. the
#     CodeBuild plan + drift roles in the CodePipeline model). Omit both for an apply-only spoke.
#
# The standardized, security-critical part is the TRUST: every trusted principal is a concrete ARN
# (no wildcard), for sts:AssumeRole + sts:TagSession. Each role trusts exactly its declared principal(s).
# The spoke supplies its own permissions. The two role names append the role type to the shared
# context render, so they are unique by construction: apply -> ck-<domain>-<name>-apply, plan ->
# ck-<domain>-<name>-plan. The suffix is a literal (not a context slot) — the role-type distinction
# isn't worth a tag; add one manually if ever needed.
locals {
  create_plan = var.hub_plan_role_arn != null || length(var.plan_principal_arns) > 0
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

  # The plan role's trusted principals, mirror of the apply side: the hub plan role (if set — GHA PR
  # previews) plus any explicit plan_principal_arns. A CodePipeline spoke adds its CodeBuild plan and
  # drift roles here so the in-pipeline Plan/Drift builds can assume the RO plan role directly.
  plan_trust_principals = distinct(concat(
    var.hub_plan_role_arn != null ? [var.hub_plan_role_arn] : [],
    var.plan_principal_arns,
  ))

  manage_roles  = var.managed_role_boundary != null
  boundary_name = "${data.context_label.this.rendered}-managed-role-boundary"

  # The boundary lives in the account whose roles it bounds — taken from the managed patterns (all
  # validated to share one account) rather than a caller-identity lookup, so the ARN is known at
  # PLAN. That matters beyond tests: the generated grant embeds this ARN in its condition, and the
  # pipeline approver should see the real policy in the plan, not "known after apply".
  boundary_account = local.manage_roles ? regex("^arn:aws:iam::([0-9]{12}):role/", var.managed_role_boundary.role_arn_patterns[0])[0] : ""
  boundary_arn     = "arn:aws:iam::${local.boundary_account}:policy/${local.boundary_name}"

  # The deploy roles' own ARNs — the set the apply role must never be able to turn on itself. Built
  # from the rendered names (which are unique by construction) rather than aws_iam_role.*.arn, so
  # they are known at PLAN time: the generated policy renders in full for review and the self-Deny
  # cannot form a cycle with the apply role that carries it. The account is wildcarded because this
  # is a Deny — matching a same-named deploy role in any account is the safer failure direction.
  self_arns = compact([
    "arn:aws:iam::*:role/${local.apply_name}",
    local.create_plan ? "arn:aws:iam::*:role/${local.plan_name}" : null,
  ])

  # The apply role's inline policy: the spoke's own document, plus the generated role-management
  # grant when the escalation guard is on.
  apply_inline_json = local.manage_roles ? data.aws_iam_policy_document.apply_combined[0].json : var.apply_inline_policy
}

# --- trust: the apply role trusts its apply principal(s); the plan role trusts its plan principal(s)
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
      identifiers = local.plan_trust_principals
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
      condition     = length(var.apply_policy_arns) > 0 || var.apply_inline_policy != null || local.manage_roles
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
  # Statically known so count resolves at plan — apply_inline_json itself renders from a document
  # that isn't final until the boundary policy exists.
  count = var.apply_inline_policy != null || local.manage_roles ? 1 : 0

  name   = "deploy-permissions"
  role   = aws_iam_role.apply.id
  policy = local.apply_inline_json
}

# --- privilege-escalation guard (opt-in via managed_role_boundary) ---------------------------
# An apply role that can mint IAM roles can otherwise mint one MORE privileged than itself:
# CreateRole -> AttachRolePolicy AdministratorAccess -> PassRole. The boundary closes that at the
# intersection — a minted role's effective permissions are (its policies ∩ this ceiling) — and the
# generated grant below is what makes the boundary unavoidable rather than merely available.
resource "aws_iam_policy" "managed_role_boundary" {
  count = local.manage_roles ? 1 : 0

  name        = local.boundary_name
  description = "Maximum permissions for any IAM role minted by ${local.apply_name}."
  policy      = var.managed_role_boundary.policy_document
  tags        = merge(data.context_tags.this.tags, { Name = local.boundary_name })
}

data "aws_iam_policy_document" "apply_combined" {
  count = local.manage_roles ? 1 : 0

  source_policy_documents = compact([var.apply_inline_policy])

  # Every action that can WIDEN a managed role's permissions, gated on that role carrying our
  # boundary. iam:PermissionsBoundary checks the boundary attached to the target principal, so a
  # role created without it — or an attempt to add a policy to an unbounded pre-existing role —
  # fails the condition and is denied.
  statement {
    sid    = "ManageBoundedRolesOnly"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = var.managed_role_boundary.role_arn_patterns

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  # Deliberately unconditioned. AWS's own boundary-delegation pattern conditions the create/attach/put
  # family above and nothing else, and a condition on an action that never populates
  # iam:PermissionsBoundary would simply never match — costing the apply role these actions entirely.
  # Safety here does not rest on that: CreateRole above IS conditioned, so every role matching the
  # patterns carries the boundary, which is equally what makes the unconditioned iam:PassRole
  # non-escalating — the role being passed is bounded by construction.
  statement {
    sid    = "ManageBoundedRolesLifecycle"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:PassRole",
    ]
    resources = var.managed_role_boundary.role_arn_patterns
  }

  # Resource "*", not the patterns: detaching a boundary is never legitimate for this role, and a
  # narrower resource would leave the action reachable on anything the patterns don't cover.
  statement {
    sid       = "NoBoundaryDetach"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  # The ceiling itself is off-limits — otherwise the role rewrites the boundary, then mints freely.
  statement {
    sid    = "NoBoundaryPolicyEdit"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.boundary_arn]
  }

  # The shortest escalation path is self-modification, and no boundary condition can close it: the
  # deploy roles carry no boundary themselves, so a pattern overlapping their ARNs would let the
  # apply role attach AdministratorAccess to ITSELF, or rewrite its own trust policy to admit an
  # arbitrary principal. Deny beats any Allow, including a spoke's own document.
  statement {
    sid       = "NoSelfModification"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = local.self_arns
  }
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
