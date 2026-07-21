# The privilege-escalation guard for a spoke whose apply role mints IAM roles. An apply role with
# unbounded iam:CreateRole can mint a principal MORE privileged than itself (CreateRole ->
# AttachRolePolicy AdministratorAccess -> PassRole), so managed_role_boundary makes the boundary
# unavoidable rather than merely available. These assertions pin the properties that make it hold:
# every widening action is boundary-conditioned, the boundary can't be detached or rewritten, and —
# the shortest path, which no boundary condition can close — the deploy roles can't modify
# themselves. Offline: dummy creds + skip_* so the policy documents render without AWS.

provider "aws" {
  region                      = "us-west-2"
  access_key                  = "testing"
  secret_key                  = "testing"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "context" {
  property_order  = ["namespace", "domain", "environment", "surface", "name", "attributes"]
  tags_value_case = "lower"
  properties = {
    namespace   = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    domain      = { validation_regex = "^[a-z0-9-]*$" }
    environment = { validation_regex = "^[a-z0-9-]*$" }
    surface     = { validation_regex = "^[a-z0-9-]*$" }
    name        = { validation_regex = "^[a-z0-9-]*$" }
    attributes  = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = {
    namespace = "ck"
    domain    = "datalake"
  }
}

variables {
  name                 = "deploy"
  apply_principal_arns = ["arn:aws:iam::883385860947:role/ck-tooling-cd-datalake-apply"]
  hub_plan_role_arn    = "arn:aws:iam::883385860947:role/ck-tooling-ci-datalake-plan"
  plan_policy_arns     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  managed_role_boundary = {
    policy_document = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:PutObject\"],\"Resource\":\"arn:aws:s3:::ck-datalake-*/*\"}]}"
    role_arn_patterns = [
      "arn:aws:iam::900303592457:role/ck-datalake-prd-*",
    ]
  }
}

run "widening_actions_require_the_boundary" {
  command = plan

  # Every action that can grant a minted role more permission is gated on iam:PermissionsBoundary
  # equalling OUR policy. Without the condition, CreateRole + AttachRolePolicy is a direct route to
  # AdministratorAccess inside the spoke account.
  assert {
    condition = alltrue([
      for action in [
        "iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePermissionsBoundary",
        ] : contains(
        one([for s in jsondecode(data.aws_iam_policy_document.apply_combined[0].json).Statement :
        s if s.Sid == "ManageBoundedRolesOnly"]).Action,
        action
      )
    ])
    error_message = "a widening IAM action is missing from the boundary-conditioned statement"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.apply_combined[0].json).Statement :
      s if s.Sid == "ManageBoundedRolesOnly"
    ]).Condition.StringEquals["iam:PermissionsBoundary"] == "arn:aws:iam::900303592457:policy/ck-datalake-deploy-managed-role-boundary"
    error_message = "the widening statement is not conditioned on this module's boundary policy"
  }
}

run "boundary_cannot_be_detached_or_rewritten" {
  command = plan

  # Resource "*" on purpose: detaching a boundary is never legitimate here, and scoping the Deny to
  # the managed patterns would leave the action reachable everywhere else.
  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.apply_combined[0].json).Statement :
      s if s.Sid == "NoBoundaryDetach"
    ]).Effect == "Deny"
    error_message = "iam:DeleteRolePermissionsBoundary is not denied — the boundary could be stripped off a minted role"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.apply_combined[0].json).Statement :
      s if s.Sid == "NoBoundaryPolicyEdit"
    ]).Resource == "arn:aws:iam::900303592457:policy/ck-datalake-deploy-managed-role-boundary"
    error_message = "the boundary policy itself is editable — the ceiling could be rewritten, then roles minted freely"
  }
}

run "deploy_roles_cannot_modify_themselves" {
  command = plan

  # The shortest escalation path, and the one a boundary CANNOT close: the deploy roles carry no
  # boundary of their own, so `attach-role-policy --role-name <apply> AdministratorAccess` would be
  # instant admin if their ARNs were ever in scope. Also covers rewriting their own trust policy.
  assert {
    condition = alltrue([
      for arn in [
        "arn:aws:iam::*:role/ck-datalake-deploy-apply",
        "arn:aws:iam::*:role/ck-datalake-deploy-plan",
        ] : contains(
        one([for s in jsondecode(data.aws_iam_policy_document.apply_combined[0].json).Statement :
        s if s.Sid == "NoSelfModification"]).Resource,
        arn
      )
    ])
    error_message = "the deploy roles' own ARNs are not denied — the apply role can attach AdministratorAccess to itself"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.apply_combined[0].json).Statement :
      s if s.Sid == "NoSelfModification"
    ]).Effect == "Deny"
    error_message = "the self-modification statement is not a Deny"
  }
}

run "managed_patterns_must_not_cover_the_deploy_roles" {
  command = plan

  # Belt to the Deny's braces: a pattern that matches the deploy roles is a design smell even though
  # the Deny overrides it. ck-datalake-prd-* covers the workload roles and excludes ck-datalake-deploy-*.
  assert {
    condition = alltrue([
      for pattern in var.managed_role_boundary.role_arn_patterns :
      !can(regex("ck-datalake-deploy", pattern))
    ])
    error_message = "a managed role pattern overlaps the deploy roles' own names"
  }
}

run "guard_is_opt_in" {
  command = plan

  variables {
    managed_role_boundary = null
    apply_policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  # A spoke whose apply role mints no roles (e.g. an admin deploy role) gets no boundary policy and
  # no generated grant — the module must stay inert rather than impose a ceiling nobody asked for.
  assert {
    condition     = length(aws_iam_policy.managed_role_boundary) == 0
    error_message = "a boundary policy was created for a spoke that did not opt in"
  }
}
