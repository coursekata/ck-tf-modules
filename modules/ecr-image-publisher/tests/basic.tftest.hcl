mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
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
    namespace   = "ck"
    domain      = "app"
    environment = "stg"
    surface     = "web"
  }
}

variables {
  name                     = "frontend"
  attributes               = "image-publish"
  github_oidc_provider_arn = "arn:aws:iam::836515410163:oidc-provider/token.actions.githubusercontent.com"
  github_repository        = "UCLATALL/coursekata"
  publish_ref              = "refs/heads/develop"
  repository_arn           = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
  boundary_checks_enabled  = false
}

run "protected_branch_publisher" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "ck-app-stg-web-frontend-image-publish"
    error_message = "the publishing role name must derive from the supplied context slots."
  }

  assert {
    condition = length([
      for condition in one(data.aws_iam_policy_document.trust.statement).condition : condition
      if condition.variable == "token.actions.githubusercontent.com:sub" &&
      contains(condition.values, "repo:UCLATALL/coursekata:ref:refs/heads/develop")
    ]) == 1
    error_message = "only the configured protected branch may assume the publishing role."
  }

  assert {
    condition = anytrue([
      for statement in data.aws_iam_policy_document.this.statement :
      contains(statement.actions, "ecr:PutImage") &&
      length(statement.resources) == 1 &&
      contains(statement.resources, var.repository_arn)
    ])
    error_message = "the publishing role must write only the configured repository."
  }

  assert {
    condition     = output.repository_arn == var.repository_arn
    error_message = "the module must expose the effective repository boundary."
  }
}

run "custom_role_and_policy_names" {
  command = plan

  variables {
    name          = "image-publish"
    attributes    = ""
    policy_suffix = "ecr-push"
  }

  assert {
    condition = (
      aws_iam_role.this.name == "ck-app-stg-web-image-publish" &&
      aws_iam_role_policy.this.name == "ck-app-stg-web-image-publish-ecr-push"
    )
    error_message = "callers must be able to preserve established role and policy names."
  }
}
