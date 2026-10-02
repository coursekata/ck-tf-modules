mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::836515410163:role/test-image-delivery" }
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
  github_oidc_provider_arn = "arn:aws:iam::836515410163:oidc-provider/token.actions.githubusercontent.com"
  github_repository        = "UCLATALL/coursekata"
  publish_ref              = "refs/heads/develop"
  candidate_repository_arn = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
  release_repository_arn   = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
}

override_data {
  target = data.aws_iam_principal_policy_simulation.stage_cannot_write_releases
  values = {
    results = [for action in [
      "ecr:BatchDeleteImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      ] : {
      action_name          = action
      allowed              = false
      decision             = "implicitDeny"
      decision_details     = {}
      matched_statements   = []
      missing_context_keys = []
      resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
    }]
  }
}

override_data {
  target = data.aws_iam_principal_policy_simulation.publish_cannot_write_candidates
  values = {
    results = [for action in [
      "ecr:BatchDeleteImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      ] : {
      action_name          = action
      allowed              = false
      decision             = "implicitDeny"
      decision_details     = {}
      matched_statements   = []
      missing_context_keys = []
      resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
    }]
  }
}

override_data {
  target = data.aws_iam_principal_policy_simulation.stage_can_write_candidates
  values = {
    results = [for action in [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
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
      resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
    }]
  }
}

override_data {
  target = data.aws_iam_principal_policy_simulation.publish_can_write_releases
  values = {
    results = [for action in [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
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
  target = data.aws_iam_principal_policy_simulation.stage_can_read_releases
  values = {
    results = [{
      action_name          = "ecr:DescribeImages"
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
  target = data.aws_iam_principal_policy_simulation.publish_can_read_candidates
  values = {
    results = [for action in [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      ] : {
      action_name          = action
      allowed              = true
      decision             = "allowed"
      decision_details     = {}
      matched_statements   = []
      missing_context_keys = []
      resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
    }]
  }
}

override_data {
  target = data.aws_iam_principal_policy_simulation.stage_can_authenticate
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

override_data {
  target = data.aws_iam_principal_policy_simulation.publish_can_authenticate
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
    target = data.aws_iam_principal_policy_simulation.stage_can_write_candidates
    values = {
      results = [for action in [
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
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
        resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "denied_permission_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.publish_can_write_releases
    values = {
      results = [for action in [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        ] : {
        action_name          = action
        allowed              = action != "ecr:DescribeImages"
        decision             = action != "ecr:DescribeImages" ? "allowed" : "implicitDeny"
        decision_details     = {}
        matched_statements   = []
        missing_context_keys = []
        resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "missing_negative_result_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.stage_cannot_write_releases
    values = {
      results = [for action in [
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        ] : {
        action_name          = action
        allowed              = false
        decision             = "implicitDeny"
        decision_details     = {}
        matched_statements   = []
        missing_context_keys = []
        resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "allowed_wrong_repository_mutation_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.publish_cannot_write_candidates
    values = {
      results = [for action in [
        "ecr:BatchDeleteImage",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        ] : {
        action_name          = action
        allowed              = action == "ecr:PutImage"
        decision             = action == "ecr:PutImage" ? "allowed" : "implicitDeny"
        decision_details     = {}
        matched_statements   = []
        missing_context_keys = []
        resource_arn         = "arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-web-frontend-image-candidate"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "missing_authentication_result_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.stage_can_authenticate
    values = {
      results = []
    }
  }

  expect_failures = [output.boundary_simulation]
}

run "denied_authentication_fails_closed" {
  command = plan

  override_data {
    target = data.aws_iam_principal_policy_simulation.publish_can_authenticate
    values = {
      results = [{
        action_name          = "ecr:GetAuthorizationToken"
        allowed              = false
        decision             = "implicitDeny"
        decision_details     = {}
        matched_statements   = []
        missing_context_keys = []
        resource_arn         = "*"
      }]
    }
  }

  expect_failures = [output.boundary_simulation]
}
