# Proves the v0.4.0 slot-drop fix for deploy roles: a per-surface spoke (e.g. the app's api
# surface, a separate repo from web) populates `surface`, so its roles render
# ck-<domain>-<surface>-<name>[-plan] — ck-app-api-deploy / ck-app-api-deploy-plan. Pre-v0.4.0
# the module dropped the surface slot, so api and web spokes would have collided on ck-app-deploy.
# The single-surface case (foundation -> ck-org-deploy) is covered in basic.tftest.hcl.

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
    domain    = "app"
    surface   = "api" # the app backend's api surface (web is a separate spoke)
  }
}

variables {
  name               = "deploy"
  hub_apply_role_arn = "arn:aws:iam::883385860947:role/ck-tooling-ci-app-api-apply"
  hub_plan_role_arn  = "arn:aws:iam::883385860947:role/ck-tooling-ci-app-api-plan"
  apply_policy_arns  = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  plan_policy_arns   = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

run "surface_renders_into_the_role_names" {
  command = plan

  assert {
    condition     = aws_iam_role.apply.name == "ck-app-api-deploy"
    error_message = "apply role must render ck-app-api-deploy (surface must NOT be dropped)"
  }
  assert {
    condition     = aws_iam_role.plan[0].name == "ck-app-api-deploy-plan"
    error_message = "plan role must render ck-app-api-deploy-plan"
  }
  assert {
    condition     = aws_iam_role.apply.tags["Surface"] == "api" && aws_iam_role.apply.tags["Domain"] == "app"
    error_message = "Domain/Surface tags must carry the populated slot values"
  }
}
