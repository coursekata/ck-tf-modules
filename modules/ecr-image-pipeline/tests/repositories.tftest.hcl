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

run "repositories_take_the_confirmed_names" {
  command = apply

  assert {
    condition = toset(concat([for r in aws_ecr_repository.this : r.name], [for r in aws_ecr_repository.cache : r.name])) == toset([
      "ck-datalake-prd-dbt-runner-image-candidate",
      "ck-datalake-prd-dbt-runner-image-release",
      "ck-datalake-prd-dbt-runner-image-cache",
    ])
    error_message = "each image gets candidate, release and cache repositories named from the context plus image-<area>"
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "candidate and release tags must be immutable, so no tag can be moved onto other bytes"
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.cache : r.image_tag_mutability == "MUTABLE"])
    error_message = "the cache repository's tags are mutable, since each release moves the month's tag"
  }

  assert {
    condition     = alltrue([for r in concat(values(aws_ecr_repository.this), values(aws_ecr_repository.cache)) : r.image_scanning_configuration[0].scan_on_push])
    error_message = "every repository must scan images on push"
  }
}

run "candidates_and_caches_expire_and_releases_do_not" {
  command = apply

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.candidate["dbt-runner/candidate"].policy).rules[0].selection.countNumber == 30 &&
      jsondecode(aws_ecr_lifecycle_policy.candidate["dbt-runner/candidate"].policy).rules[0].selection.countType == "sinceImagePushed" &&
      jsondecode(aws_ecr_lifecycle_policy.candidate["dbt-runner/candidate"].policy).rules[0].selection.tagStatus == "any"
    )
    error_message = "candidate images and caches expire 30 days after push, tagged or not"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy).rules[0].selection.countNumber == 62 &&
      jsondecode(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy).rules[0].selection.tagStatus == "any"
    )
    error_message = "released caches, tagged or not, expire 62 days after push"
  }

  assert {
    condition     = strcontains(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy, "\"countNumber\":62")
    error_message = "countNumber must render as a JSON number"
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.candidate) == 1 && length(aws_ecr_lifecycle_policy.cache) == 1
    error_message = "released images never expire: a deployed digest must stay pullable"
  }
}

run "two_images_get_six_repositories" {
  command = apply

  variables {
    images = ["web", "worker"]
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 4 && length(aws_ecr_repository.cache) == 2 && contains(keys(aws_ecr_repository.cache), "worker/cache")
    error_message = "each image gets its own three repositories"
  }
}
