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
  stage_attributes         = "image-stage"
  publish_attributes       = "image-publish"
  github_oidc_provider_arn = "arn:aws:iam::836515410163:oidc-provider/token.actions.githubusercontent.com"
  github_repository        = "UCLATALL/coursekata"
  publish_ref              = "refs/heads/develop"
  candidate_repository_arn = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
  release_repository_arn   = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
  boundary_checks_enabled  = false
}

run "roles_and_repository_boundaries" {
  command = plan

  assert {
    condition = (
      aws_iam_role.stage.name == "ck-app-stg-web-frontend-image-stage" &&
      aws_iam_role.publish.name == "ck-app-stg-web-frontend-image-publish"
    )
    error_message = "role names must derive from the supplied context slots."
  }

  assert {
    condition = (
      one(data.aws_iam_policy_document.stage_trust.statement).effect == "Allow" &&
      contains(one(data.aws_iam_policy_document.stage_trust.statement).actions, "sts:AssumeRoleWithWebIdentity") &&
      contains(one(one(data.aws_iam_policy_document.stage_trust.statement).principals).identifiers, var.github_oidc_provider_arn) &&
      length([
        for condition in one(data.aws_iam_policy_document.stage_trust.statement).condition : condition
        if condition.variable == "token.actions.githubusercontent.com:sub" &&
        contains(condition.values, "repo:UCLATALL/coursekata:pull_request")
      ]) == 1
    )
    error_message = "the staging role must trust only this repository's pull-request subject."
  }

  assert {
    condition = length([
      for condition in one(data.aws_iam_policy_document.publish_trust.statement).condition : condition
      if condition.variable == "token.actions.githubusercontent.com:sub" &&
      contains(condition.values, "repo:UCLATALL/coursekata:ref:refs/heads/develop")
    ]) == 1
    error_message = "the promotion role must trust only the configured branch subject."
  }

  assert {
    condition = (
      anytrue([
        for statement in data.aws_iam_policy_document.stage.statement :
        contains(statement.actions, "ecr:PutImage") &&
        contains(statement.resources, var.candidate_repository_arn)
      ]) &&
      alltrue([
        for statement in data.aws_iam_policy_document.stage.statement :
        !contains(statement.actions, "ecr:PutImage") ||
        !contains(statement.resources, var.release_repository_arn)
      ])
    )
    error_message = "the staging role must write candidates and must not write releases."
  }

  assert {
    condition = (
      anytrue([
        for statement in data.aws_iam_policy_document.publish.statement :
        contains(statement.actions, "ecr:PutImage") &&
        contains(statement.resources, var.release_repository_arn)
      ]) &&
      alltrue([
        for statement in data.aws_iam_policy_document.publish.statement :
        !contains(statement.actions, "ecr:PutImage") ||
        !contains(statement.resources, var.candidate_repository_arn)
      ])
    )
    error_message = "the promotion role must write releases and must not write candidates."
  }

  assert {
    condition = alltrue([
      for action in [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
        ] : anytrue([
          for statement in data.aws_iam_policy_document.publish.statement :
          contains(statement.actions, action) &&
          contains(statement.resources, var.candidate_repository_arn)
      ])
    ])
    error_message = "the promotion role must be able to read candidate manifests and layers."
  }

  assert {
    condition = anytrue([
      for statement in data.aws_iam_policy_document.stage.statement :
      contains(statement.actions, "ecr:DescribeImages") &&
      contains(statement.resources, var.release_repository_arn)
    ])
    error_message = "the staging role must be able to detect an already released image."
  }

  assert {
    condition = (
      output.candidate_repository_arn == var.candidate_repository_arn &&
      output.release_repository_arn == var.release_repository_arn
    )
    error_message = "the module must expose the effective repository boundary for consumer wiring tests."
  }
}

run "custom_role_and_policy_names" {
  command = plan

  variables {
    stage_name            = "image-stage"
    stage_attributes      = ""
    publish_name          = "image-publish"
    publish_attributes    = ""
    stage_policy_suffix   = "ecr-push-staging"
    publish_policy_suffix = "ecr-push"
  }

  assert {
    condition = (
      aws_iam_role.stage.name == "ck-app-stg-web-image-stage" &&
      aws_iam_role.publish.name == "ck-app-stg-web-image-publish"
    )
    error_message = "callers must be able to preserve established role names while adopting the shared module."
  }

  assert {
    condition = (
      aws_iam_role_policy.stage.name == "ck-app-stg-web-image-stage-ecr-push-staging" &&
      aws_iam_role_policy.publish.name == "ck-app-stg-web-image-publish-ecr-push"
    )
    error_message = "callers must be able to preserve established inline policy names while adopting the shared module."
  }
}
