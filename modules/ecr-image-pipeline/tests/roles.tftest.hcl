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

run "roles_take_the_confirmed_names" {
  command = apply

  assert {
    condition = (
      aws_iam_role.this["candidate"].name == "ck-datalake-prd-image-candidate" &&
      aws_iam_role.this["cache-read"].name == "ck-datalake-prd-image-cache-read" &&
      aws_iam_role.this["release"].name == "ck-datalake-prd-image-release"
    )
    error_message = "the roles are named from the context plus image-candidate, image-cache-read and image-release"
  }
}

run "each_role_trusts_only_its_own_subject" {
  command = apply

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["candidate"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 &&
      contains(c.values, "repo:coursekata/ck-datalake:ref:refs/heads/main")
    ]) == 1
    error_message = "the candidate role trusts only a push to the default branch"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["cache-read"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 &&
      contains(c.values, "repo:coursekata/ck-datalake:pull_request")
    ]) == 1
    error_message = "the cache-read role trusts only the repository's pull requests"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 &&
      contains(c.values, "repo:coursekata/ck-datalake:environment:release")
    ]) == 1
    error_message = "the release role trusts only jobs in the repository's release environment"
  }

  assert {
    condition = alltrue([for k in keys(aws_iam_role.this) : length([
      for c in one(data.aws_iam_policy_document.trust[k].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:aud" && contains(c.values, "sts.amazonaws.com")
    ]) == 1])
    error_message = "every role, readers included, requires the sts.amazonaws.com audience"
  }
}

run "the_candidate_role_follows_another_default_branch" {
  command = apply

  variables {
    default_branch = "develop"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["candidate"].statement).condition : c
      if contains(c.values, "repo:coursekata/ck-datalake:ref:refs/heads/develop")
    ]) == 1
    error_message = "the candidate role trusts a push to whatever the default branch is"
  }
}

run "the_candidate_role_writes_candidates_and_reads_only_the_cache" {
  command = apply

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["candidate"].statement : s.resources if s.sid == "Write"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-candidate"])
    error_message = "a default-branch build may push only to the candidate repository"
  }

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["candidate"].statement : s.resources if s.sid == "Read"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-cache"])
    error_message = "a default-branch build reads the release cache and nothing else"
  }
}

run "the_cache_read_role_only_reads_the_cache" {
  command = apply

  assert {
    condition     = length([for s in data.aws_iam_policy_document.permissions["cache-read"].statement : s if s.sid == "Write"]) == 0
    error_message = "a pull request may write nothing"
  }

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["cache-read"].statement : s.resources if s.sid == "Read"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-cache"])
    error_message = "a pull request reads only the release cache"
  }

  assert {
    condition = !contains(one([
      for s in data.aws_iam_policy_document.permissions["cache-read"].statement : s.actions if s.sid == "Read"
    ]), "ecr:PutImage")
    error_message = "the read statement must carry no push action"
  }
}

run "the_release_role_writes_releases_and_reads_candidates" {
  command = apply

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["release"].statement : s.resources if s.sid == "Write"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-release", "arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-cache"])
    error_message = "the release role writes the release image and cache repositories"
  }

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["release"].statement : s.resources if s.sid == "Read"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-candidate"])
    error_message = "the release role reads only the candidate repository"
  }
}

run "no_role_can_delete_or_loosen_a_repository" {
  command = apply

  variables {
    release_readers = { "coursekata/ck-datalake" = "main" }
  }

  assert {
    condition     = length(aws_iam_role.this) == 4
    error_message = "this run covers the three roles and a reader"
  }

  assert {
    condition = alltrue([for k in keys(aws_iam_role.this) : anytrue([
      for s in data.aws_iam_policy_document.permissions[k].statement :
      s.effect == "Deny" && contains(s.actions, "ecr:BatchDeleteImage") &&
      contains(s.actions, "ecr:PutLifecyclePolicy") && length(s.resources) == 3
    ])])
    error_message = "every role is denied image deletion and lifecycle changes on all three repositories"
  }

  assert {
    condition = alltrue([for k in keys(aws_iam_role.this) : alltrue([
      for s in data.aws_iam_policy_document.permissions[k].statement :
      s.effect == "Deny" || length(setintersection(toset(s.actions), toset([
        "ecr:BatchDeleteImage", "ecr:DeleteLifecyclePolicy", "ecr:DeleteRepository", "ecr:DeleteRepositoryPolicy",
        "ecr:PutImageTagMutability", "ecr:PutLifecyclePolicy", "ecr:SetRepositoryPolicy",
      ]))) == 0
    ])])
    error_message = "no allow statement may grant a destructive or loosening action"
  }
}

run "two_images_share_the_three_roles" {
  command = apply

  variables {
    images = ["web", "worker"]
  }

  assert {
    condition = length(aws_iam_role.this) == 3 && toset(one([
      for s in data.aws_iam_policy_document.permissions["candidate"].statement : s.resources if s.sid == "Write"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-web-image-candidate", "arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-worker-image-candidate"])
    error_message = "one set of roles serves every image of the repository"
  }
}

run "the_immutable_subject_form_is_accepted" {
  command = apply

  variables {
    github_repository = "coursekata@123/ckhub@456"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release"].statement).condition : c
      if contains(c.values, "repo:coursekata@123/ckhub@456:environment:release")
    ]) == 1
    error_message = "a repository created after 2026-07-15 is trusted in GitHub's immutable subject form"
  }
}

# A consumer named in release_readers gets a role its default-branch jobs may assume, which reads the
# release repositories and nothing else. ck-datalake names itself; ck-app-tf is the frontend's reader.
run "a_release_reader_reads_releases_and_nothing_else" {
  command = apply

  variables {
    release_readers = { "coursekata/ck-datalake" = "main" }
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release-read/coursekata/ck-datalake"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 && contains(c.values, "repo:coursekata/ck-datalake:ref:refs/heads/main")
    ]) == 1
    error_message = "a reader is trusted on its default branch, and on nothing else"
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.permissions["release-read/coursekata/ck-datalake"].statement : s if s.sid == "Write"]) == 0
    error_message = "a reader writes nothing"
  }

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["release-read/coursekata/ck-datalake"].statement : s.resources if s.sid == "Read"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-release"])
    error_message = "a reader reads only the release repositories"
  }

  assert {
    condition = length(setintersection(toset(one([
      for s in data.aws_iam_policy_document.permissions["release-read/coursekata/ck-datalake"].statement : s.actions if s.sid == "Read"
    ])), toset(["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]))) == 0
    error_message = "a reader's read statement carries no push action"
  }

  assert {
    condition     = output.release_read_role_arns["coursekata/ck-datalake"] == aws_iam_role.this["release-read/coursekata/ck-datalake"].arn
    error_message = "the reader's role is output by its repository"
  }

  assert {
    condition     = aws_iam_role.this["release-read/coursekata/ck-datalake"].name == "ck-datalake-prd-image-release-read-coursekata-ck-datalake"
    error_message = "the reader's role is named for its repository, with the slashes rendered as hyphens"
  }
}

# A reader's default branch is its own: the frontend is released from develop, and its consumer,
# ck-app-tf, runs Renovate on main.
run "a_reader_is_trusted_on_its_own_default_branch" {
  command = apply

  variables {
    default_branch  = "develop"
    release_readers = { "coursekata/ck-app-tf" = "main" }
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release-read/coursekata/ck-app-tf"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 && contains(c.values, "repo:coursekata/ck-app-tf:ref:refs/heads/main")
    ]) == 1
    error_message = "the reader is trusted on the branch it names, not the producer's"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["candidate"].statement).condition : c
      if contains(c.values, "repo:coursekata/ck-datalake:ref:refs/heads/develop")
    ]) == 1
    error_message = "the producer's own roles still follow the producer's default branch"
  }
}

# The role name takes only [a-z0-9-] and at most 64 characters. A reader in GitHub's immutable
# subject form keeps its ids in the trust and drops them from the name, and uppercase and dots render
# as the label allows, so a repository can move to the immutable form without a new role.
run "a_reader_in_the_immutable_form_or_with_uppercase_still_names_a_role" {
  command = apply

  variables {
    release_readers = {
      "coursekata@12345678/ck-datalake@1098765432" = "main"
      "UCLATALL/course.kata"                       = "develop"
    }
  }

  assert {
    condition     = aws_iam_role.this["release-read/coursekata@12345678/ck-datalake@1098765432"].name == "ck-datalake-prd-image-release-read-coursekata-ck-datalake"
    error_message = "the immutable form names the same role as the plain form"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release-read/coursekata@12345678/ck-datalake@1098765432"].statement).condition : c
      if contains(c.values, "repo:coursekata@12345678/ck-datalake@1098765432:ref:refs/heads/main")
    ]) == 1
    error_message = "the trust keeps the subject exactly as GitHub writes it"
  }

  assert {
    condition     = aws_iam_role.this["release-read/UCLATALL/course.kata"].name == "ck-datalake-prd-image-release-read-uclatall-course-kata"
    error_message = "uppercase and dots render as the label allows"
  }
}

# Two readers whose names render alike would fail at apply with one role; the plan must fail first.
run "rejects_readers_whose_role_names_collide" {
  command = plan

  variables {
    release_readers = { "a/b-c" = "main", "a-b/c" = "main" }
  }

  expect_failures = [aws_iam_role.this]
}

run "no_readers_means_no_reader_roles" {
  command = apply

  assert {
    condition     = length([for k, _ in aws_iam_role.this : k if startswith(k, "release-read/")]) == 0 && length(output.release_read_role_arns) == 0
    error_message = "the three roles alone, as before"
  }
}
