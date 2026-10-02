mock_provider "aws" {}

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
  values = { namespace = "ck", domain = "datalake", environment = "stg" }
}

variables {
  name       = "dbt-runner"
  attributes = "image"
}

run "release_repository_expires_by_count_only" {
  command = plan
  variables {
    retain_n_images = 100
  }

  assert {
    condition     = aws_ecr_lifecycle_policy.this.repository == aws_ecr_repository.this.name
    error_message = "lifecycle policy must attach to this module's repository"
  }

  assert {
    condition = anytrue([
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules :
      r.selection.countType == "imageCountMoreThan" && r.selection.countNumber == 100
    ])
    error_message = "a repository given retain_n_images must expire by count at that number"
  }

  assert {
    condition = !anytrue([
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules :
      r.selection.countType == "sinceImagePushed"
    ])
    error_message = "retain_n_images is set, so no age rule may apply"
  }

  assert {
    condition = length(jsondecode(aws_ecr_lifecycle_policy.this.policy).rules) == 1 && !anytrue([
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules : can(r.selection.countUnit)
    ])
    error_message = "a count rule must render alone and without countUnit"
  }

  assert {
    condition     = strcontains(aws_ecr_lifecycle_policy.this.policy, "\"countNumber\":100")
    error_message = "countNumber must render as a JSON number, not a quoted string"
  }
}

run "candidate_repository_expires_by_age_only" {
  command = plan
  variables {
    expire_after_days = 30
  }

  assert {
    condition = anytrue([
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules :
      r.selection.countType == "sinceImagePushed" && r.selection.countUnit == "days" && r.selection.countNumber == 30
    ])
    error_message = "a repository given expire_after_days must expire by age at that number of days, and sinceImagePushed requires countUnit"
  }

  assert {
    condition     = strcontains(aws_ecr_lifecycle_policy.this.policy, "\"countNumber\":30")
    error_message = "countNumber must render as a JSON number, not a quoted string"
  }

  assert {
    condition = !anytrue([
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules :
      r.selection.countType == "imageCountMoreThan"
    ])
    error_message = "expire_after_days is set, so no count rule may apply"
  }
}

run "no_rule_singles_out_untagged_images" {
  command = plan
  variables {
    retain_n_images = 100
  }

  assert {
    condition = !anytrue([
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules :
      r.selection.tagStatus == "untagged"
    ])
    error_message = "an untagged-only rule would expire a digest a running task definition may still name"
  }
}

run "rejects_both_retention_rules" {
  command = plan
  variables {
    retain_n_images   = 100
    expire_after_days = 30
  }

  expect_failures = [aws_ecr_lifecycle_policy.this]
}

run "rejects_neither_retention_rule" {
  command = plan

  expect_failures = [aws_ecr_lifecycle_policy.this]
}

run "rejects_zero_retention" {
  command = plan
  variables {
    retain_n_images = 0
  }

  expect_failures = [var.retain_n_images]
}

run "rejects_fractional_expiry_days" {
  command = plan
  variables {
    expire_after_days = 1.5
  }

  expect_failures = [var.expire_after_days]
}

run "rejects_attribute_with_a_trailing_dash" {
  command = plan
  variables {
    retain_n_images = 100
    attributes      = "image-staging-"
  }

  expect_failures = [data.context_tags.this]
}
