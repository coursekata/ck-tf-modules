mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "903709589067" }
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
  values = { namespace = "ck", domain = "datalake", environment = "prd" }
}

variables {
  images                   = ["dbt-runner"]
  github_oidc_provider_arn = "arn:aws:iam::903709589067:oidc-provider/token.actions.githubusercontent.com"
  github_repository        = "coursekata/ck-datalake"
}

run "rejects_no_images" {
  command = plan
  variables {
    images = []
  }
  expect_failures = [var.images]
}

run "rejects_a_bad_image_name" {
  command = plan
  variables {
    images = ["Dbt_Runner"]
  }
  expect_failures = [var.images]
}

run "rejects_a_repository_with_one_id" {
  command = plan
  variables {
    github_repository = "coursekata@123/ckhub"
  }
  expect_failures = [var.github_repository]
}

run "rejects_a_subject_suffix" {
  command = plan
  variables {
    github_repository = "coursekata/ck-datalake:ref:refs/heads/main"
  }
  expect_failures = [var.github_repository]
}

run "rejects_another_oidc_provider" {
  command = plan
  variables {
    github_oidc_provider_arn = "arn:aws:iam::903709589067:oidc-provider/accounts.google.com"
  }
  expect_failures = [var.github_oidc_provider_arn]
}

run "rejects_a_ref_as_the_default_branch" {
  command = plan
  variables {
    default_branch = "refs/heads/main"
  }
  expect_failures = [var.default_branch]
}

run "rejects_a_default_branch_with_a_colon" {
  command = plan
  variables {
    default_branch = "main:x"
  }
  expect_failures = [var.default_branch]
}

run "rejects_a_reader_in_neither_subject_form" {
  command = plan

  variables {
    release_readers = { "ck-datalake" = "main" }
  }

  expect_failures = [var.release_readers]
}

run "rejects_a_reader_branch_given_as_a_ref" {
  command = plan

  variables {
    release_readers = { "coursekata/ck-datalake" = "refs/heads/main" }
  }

  expect_failures = [var.release_readers]
}
