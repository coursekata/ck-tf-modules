mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::836515410163:role/ck-app-stg-web-frontend-image-publish"
    }
  }

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
}

override_data {
  target = data.aws_iam_principal_policy_simulation.can_publish
  values = {
    results = [for action in [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      ] : {
      action_name          = action
      allowed              = true
      decision             = "allowed"
      decision_details     = {}
      matched_statements   = []
      missing_context_keys = []
      resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
    }]
  }
}

override_data {
  target = data.aws_iam_principal_policy_simulation.can_authenticate
  values = {
    results = [{
      action_name          = "ecr:GetAuthorizationToken"
      allowed              = true
      decision             = "allowed"
      decision_details     = {}
      matched_statements   = []
      missing_context_keys = []
      resource_arn         = "*"
    }]
  }
}

run "complete_allowed_results_pass" {
  command = apply
}

run "missing_result_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.can_publish
    values = {
      results = [for action in [
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        ] : {
        action_name          = action
        allowed              = true
        decision             = "allowed"
        decision_details     = {}
        matched_statements   = []
        missing_context_keys = []
        resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "denied_permission_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.can_publish
    values = {
      results = [for action in [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        ] : {
        action_name          = action
        allowed              = action != "ecr:PutImage"
        decision             = action != "ecr:PutImage" ? "allowed" : "implicitDeny"
        decision_details     = {}
        matched_statements   = []
        missing_context_keys = []
        resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "missing_authentication_result_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.can_authenticate
    values = { results = [] }
  }

  expect_failures = [output.boundary_simulation]
}
