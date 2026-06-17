# Unit tests for the deploy-roles module. The real aws provider runs OFFLINE (dummy creds +
# skip_* so aws_iam_policy_document renders for the trust assertions); aws_caller_identity is
# overridden. The context provider is configured per the org standard, WITH `attributes` so the
# plan role can render <...>-plan. Assertions pin the security-critical trust: each role trusts
# EXACTLY its hub CI role, never a wildcard, never the other role's CI principal.

provider "aws" {
  region                      = "us-west-2"
  access_key                  = "testing"
  secret_key                  = "testing"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "context" {
  property_order  = ["namespace", "tenant", "name", "attributes"]
  tags_value_case = "lower"
  properties = {
    namespace  = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    tenant     = { validation_regex = "^[a-z0-9-]*$" }
    name       = { validation_regex = "^[a-z0-9-]*$" }
    attributes = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = {
    namespace = "ck"
    tenant    = "org" # foundation's tenant -> ck-org-deploy[-plan]
  }
}

# Resolve the account guard to the foundation spoke account for every run; wrong_account overrides.
override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "232672477651"
  }
}

variables {
  expected_account_id = "232672477651"
  hub_apply_role_arn  = "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-apply"
  hub_plan_role_arn   = "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-plan"
  apply_policy_arns   = ["arn:aws:iam::aws:policy/AdministratorAccess"] # placeholder perms for the test
  plan_policy_arns    = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

run "names_render_from_context" {
  command = plan

  assert {
    condition     = aws_iam_role.apply.name == "ck-org-deploy"
    error_message = "apply role must render as ck-org-deploy"
  }
  assert {
    condition     = aws_iam_role.plan[0].name == "ck-org-deploy-plan"
    error_message = "plan role must render as ck-org-deploy-plan"
  }
  assert {
    condition     = aws_iam_role.apply.tags["Name"] == "ck-org-deploy"
    error_message = "Name tag must pin the full role id"
  }
}

run "trust_is_exact_per_hub_role" {
  command = plan

  # Apply role trusts EXACTLY the hub APPLY role, AssumeRole + TagSession.
  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-apply")
    error_message = "apply role must trust the hub apply CI role"
  }
  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "sts:AssumeRole") && strcontains(aws_iam_role.apply.assume_role_policy, "sts:TagSession")
    error_message = "apply trust must allow sts:AssumeRole + sts:TagSession"
  }
  # ...and NEVER the plan CI role (cross-trust would let a PR run reach the write path).
  assert {
    condition     = !strcontains(aws_iam_role.apply.assume_role_policy, "ck-tooling-ci-foundation-plan")
    error_message = "apply role must NOT trust the plan CI role"
  }
  # Plan role trusts EXACTLY the hub PLAN role, never the apply role.
  assert {
    condition     = strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-tooling-ci-foundation-plan") && !strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-tooling-ci-foundation-apply")
    error_message = "plan role must trust only the plan CI role"
  }
  # No wildcard principal in either trust.
  assert {
    condition     = !strcontains(aws_iam_role.apply.assume_role_policy, "\"AWS\":\"*\"") && !strcontains(aws_iam_role.plan[0].assume_role_policy, "\"AWS\":\"*\"")
    error_message = "trust must name an exact principal ARN, never *"
  }
}

run "apply_only_spoke_omits_plan_role" {
  command = plan

  variables {
    hub_plan_role_arn = null
    plan_policy_arns  = []
  }

  assert {
    condition     = length(aws_iam_role.plan) == 0
    error_message = "an apply-only spoke (hub_plan_role_arn = null) must create NO plan role"
  }
  assert {
    condition     = aws_iam_role.apply.name == "ck-org-deploy"
    error_message = "the apply role is still created for an apply-only spoke"
  }
}

run "wrong_account_is_rejected" {
  command = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "000000000000"
    }
  }

  expect_failures = [
    aws_iam_role.apply,
  ]
}

run "permissionless_apply_role_is_rejected" {
  command = plan

  variables {
    apply_policy_arns   = []
    apply_inline_policy = null
  }

  expect_failures = [
    aws_iam_role.apply,
  ]
}

run "permissionless_plan_role_is_rejected" {
  command = plan

  variables {
    plan_policy_arns   = []
    plan_inline_policy = null
  }

  expect_failures = [
    aws_iam_role.plan,
  ]
}
