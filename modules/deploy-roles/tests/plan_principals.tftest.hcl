# The plan role can trust a non-GHA executor (the CodePipeline delivery model): plan_principal_arns
# adds the CodeBuild plan + drift roles, so the in-pipeline Plan and Drift builds assume the RO plan
# role directly — the mirror of apply_principal_arns. Set alongside hub_plan_role_arn (GHA still
# previews PRs) or in place of it (a pipeline-only plan path). Wildcards and account-roots rejected.

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
  name               = "deploy"
  hub_apply_role_arn = "arn:aws:iam::883385860947:role/ck-tooling-ci-datalake-apply"
  apply_policy_arns  = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  plan_policy_arns   = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

run "plan_trusts_hub_and_codebuild_together" {
  command = plan

  variables {
    hub_plan_role_arn = "arn:aws:iam::883385860947:role/ck-tooling-ci-datalake-plan"
    plan_principal_arns = [
      "arn:aws:iam::883385860947:role/ck-cd-prd-datalake-lake-plan",
      "arn:aws:iam::883385860947:role/ck-cd-prd-datalake-lake-drift",
    ]
  }

  assert {
    condition     = strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-tooling-ci-datalake-plan") && strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-cd-prd-datalake-lake-plan") && strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-cd-prd-datalake-lake-drift")
    error_message = "plan trust must include the hub plan role and both CodeBuild plan/drift principals"
  }
}

run "plan_trusts_only_codebuild_when_hub_null" {
  command = plan

  variables {
    hub_plan_role_arn   = null
    plan_principal_arns = ["arn:aws:iam::883385860947:role/ck-cd-prd-datalake-lake-plan"]
  }

  # the plan role is still created — create_plan keys off plan_principal_arns too.
  assert {
    condition     = strcontains(aws_iam_role.plan[0].assume_role_policy, "ck-cd-prd-datalake-lake-plan") && !strcontains(aws_iam_role.plan[0].assume_role_policy, "ci-datalake-plan")
    error_message = "with hub_plan_role_arn null, plan must trust only the CodeBuild principal (pipeline-only plan path)"
  }
  # never a wildcard principal.
  assert {
    condition     = !strcontains(aws_iam_role.plan[0].assume_role_policy, "\"AWS\":\"*\"")
    error_message = "plan trust must name exact principal ARNs, never *"
  }
}

run "apply_only_spoke_creates_no_plan_role" {
  command = plan

  variables {
    hub_plan_role_arn   = null
    plan_principal_arns = []
  }

  assert {
    condition     = length(aws_iam_role.plan) == 0
    error_message = "with neither hub_plan_role_arn nor plan_principal_arns, no plan role must be created"
  }
}

run "partial_wildcard_plan_principal_is_rejected" {
  command = plan

  variables {
    plan_principal_arns = ["arn:aws:iam::883385860947:role/deploy-*"]
  }

  expect_failures = [var.plan_principal_arns]
}

run "account_root_plan_principal_is_rejected" {
  command = plan

  variables {
    plan_principal_arns = ["arn:aws:iam::883385860947:root"]
  }

  expect_failures = [var.plan_principal_arns]
}
