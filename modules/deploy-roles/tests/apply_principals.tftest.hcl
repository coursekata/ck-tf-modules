# The apply role can trust a non-GHA executor (the CodePipeline delivery model): apply_principal_arns
# adds the CodeBuild apply role, and setting hub_apply_role_arn = null retires the GHA apply path so
# the apply role trusts ONLY CodeBuild while the plan role still trusts the hub plan role — the split
# model (GHA plans, CodePipeline applies). A trustless apply role (neither set) is rejected.

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
    domain    = "datalake" # the spoke deploy roles -> ck-datalake-deploy[-apply/-plan]
  }
}

variables {
  name              = "deploy"
  hub_plan_role_arn = "arn:aws:iam::883385860947:role/ck-tooling-ci-datalake-plan"
  plan_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  apply_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

run "apply_trusts_hub_and_codebuild_together" {
  command = plan

  variables {
    hub_apply_role_arn   = "arn:aws:iam::883385860947:role/ck-tooling-ci-datalake-apply"
    apply_principal_arns = ["arn:aws:iam::883385860947:role/ck-cd-prd-datalake-lake-apply"]
  }

  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "ck-tooling-ci-datalake-apply") && strcontains(aws_iam_role.apply.assume_role_policy, "ck-cd-prd-datalake-lake-apply")
    error_message = "apply trust must include both the hub apply role and the additional CodeBuild apply principal"
  }
}

run "apply_trusts_only_codebuild_when_hub_null" {
  command = plan

  variables {
    hub_apply_role_arn   = null
    apply_principal_arns = ["arn:aws:iam::883385860947:role/ck-cd-prd-datalake-lake-apply"]
  }

  # apply trusts CodeBuild, NOT the retired GHA hub apply role.
  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "ck-cd-prd-datalake-lake-apply") && !strcontains(aws_iam_role.apply.assume_role_policy, "ci-datalake-apply")
    error_message = "with hub_apply_role_arn null, apply must trust only the CodeBuild principal (GHA apply path retired)"
  }
  # the plan role still trusts the hub plan role (GHA still plans).
  assert {
    condition     = strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-tooling-ci-datalake-plan")
    error_message = "the plan role still trusts the hub plan role (split model: GHA plans, CodePipeline applies)"
  }
  # never a wildcard principal.
  assert {
    condition     = !strcontains(aws_iam_role.apply.assume_role_policy, "\"AWS\":\"*\"")
    error_message = "apply trust must name exact principal ARNs, never *"
  }
}

run "trustless_apply_role_is_rejected" {
  command = plan

  variables {
    hub_apply_role_arn   = null
    apply_principal_arns = []
  }

  expect_failures = [
    aws_iam_role.apply,
  ]
}

# The least-privilege trust guarantee: the ARN validations must reject anything but a concrete
# arn:aws:iam::<12>:role/<name> — partial wildcards, account-root, and role-wildcards all rejected,
# so a loosened regex fails CI (the rendered "AWS":"*" substring check can't catch these forms).
run "partial_wildcard_apply_principal_is_rejected" {
  command = plan

  variables {
    hub_apply_role_arn   = null
    apply_principal_arns = ["arn:aws:iam::883385860947:role/deploy-*"]
  }

  expect_failures = [var.apply_principal_arns]
}

run "account_root_apply_principal_is_rejected" {
  command = plan

  variables {
    hub_apply_role_arn   = null
    apply_principal_arns = ["arn:aws:iam::883385860947:root"]
  }

  expect_failures = [var.apply_principal_arns]
}

run "wildcard_hub_apply_role_is_rejected" {
  command = plan

  variables {
    hub_apply_role_arn = "arn:aws:iam::883385860947:role/*"
  }

  expect_failures = [var.hub_apply_role_arn]
}
