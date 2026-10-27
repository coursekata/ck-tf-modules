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
    condition     = alltrue([for k, r in aws_ecr_repository.this : r.image_tag_mutability == (endswith(k, "/release") ? "IMMUTABLE_WITH_EXCLUSION" : "IMMUTABLE")])
    error_message = "candidate tags are immutable; release tags are immutable apart from the one excluded name"
  }

  assert {
    condition = alltrue([for k, r in aws_ecr_repository.this : endswith(k, "/release")
      ? length(r.image_tag_mutability_exclusion_filter) == 1 && one(r.image_tag_mutability_exclusion_filter).filter == "latest" && one(r.image_tag_mutability_exclusion_filter).filter_type == "WILDCARD"
      : length(r.image_tag_mutability_exclusion_filter) == 0
    ])
    error_message = "only a release repository excludes a name, and the one name is latest, which each release moves for development pulls"
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.cache : r.image_tag_mutability == "MUTABLE"])
    error_message = "the cache repository's tags are mutable, since each release moves the cache tag"
  }

  assert {
    condition     = alltrue([for r in concat(values(aws_ecr_repository.this), values(aws_ecr_repository.cache)) : r.image_scanning_configuration[0].scan_on_push])
    error_message = "every repository must scan images on push"
  }
}

run "candidates_and_replaced_caches_expire_and_releases_do_not" {
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
      length(jsondecode(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy).rules) == 1 &&
      jsondecode(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy).rules[0].selection.countNumber == 7 &&
      jsondecode(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy).rules[0].selection.countType == "sinceImagePushed" &&
      jsondecode(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy).rules[0].selection.tagStatus == "untagged"
    )
    error_message = "untagged caches expire 7 days after push, and the tagged cache never expires"
  }

  assert {
    condition     = strcontains(aws_ecr_lifecycle_policy.cache["dbt-runner/cache"].policy, "\"countNumber\":7")
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

run "the_default_names_keep_the_image_qualifier" {
  command = apply

  assert {
    condition     = aws_ecr_repository.this["dbt-runner/release"].name == "ck-datalake-prd-dbt-runner-image-release"
    error_message = "the lake's repositories keep their names: an ECR repository cannot be renamed"
  }
}

run "without_the_qualifier_the_area_alone_follows_the_name" {
  command = apply

  variables {
    images                   = ["server", "contract"]
    image_qualifier_in_names = false
  }

  assert {
    condition = toset(concat([for r in aws_ecr_repository.this : r.name], [for r in aws_ecr_repository.cache : r.name])) == toset([
      "ck-datalake-prd-server-candidate", "ck-datalake-prd-server-release", "ck-datalake-prd-server-cache",
      "ck-datalake-prd-contract-candidate", "ck-datalake-prd-contract-release", "ck-datalake-prd-contract-cache",
    ])
    error_message = "a repository is the context, the image's name and its area"
  }
}
