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
    release_readers = { datalake = { repository = "coursekata/ck-datalake", branch = "main" } }
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
# release repositories and nothing else. ck-datalake names itself; ck-app-web is the api's reader.
run "a_release_reader_reads_releases_and_nothing_else" {
  command = apply

  variables {
    release_readers = { datalake = { repository = "coursekata/ck-datalake", branch = "main" } }
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release-read/datalake"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 && contains(c.values, "repo:coursekata/ck-datalake:ref:refs/heads/main")
    ]) == 1
    error_message = "a reader is trusted on its default branch, and on nothing else"
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.permissions["release-read/datalake"].statement : s if s.sid == "Write"]) == 0
    error_message = "a reader writes nothing"
  }

  assert {
    condition = toset(one([
      for s in data.aws_iam_policy_document.permissions["release-read/datalake"].statement : s.resources if s.sid == "Read"
    ])) == toset(["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-dbt-runner-image-release"])
    error_message = "a reader reads only the release repositories"
  }

  assert {
    condition = length(setintersection(toset(one([
      for s in data.aws_iam_policy_document.permissions["release-read/datalake"].statement : s.actions if s.sid == "Read"
    ])), toset(["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]))) == 0
    error_message = "a reader's read statement carries no push action"
  }

  assert {
    condition     = output.release_read_role_arns["datalake"] == aws_iam_role.this["release-read/datalake"].arn
    error_message = "the reader's role is output by its label"
  }

  assert {
    condition     = aws_iam_role.this["release-read/datalake"].name == "ck-datalake-prd-image-release-read-datalake"
    error_message = "the reader's role is named by its label"
  }
}

# A reader's default branch is its own: the api is released from develop, and its consumer,
# ck-app-web, runs Renovate on main.
run "a_reader_is_trusted_on_its_own_default_branch" {
  command = apply

  variables {
    default_branch  = "develop"
    release_readers = { web = { repository = "coursekata/ck-app-web", branch = "main" } }
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release-read/web"].statement).condition : c
      if c.variable == "token.actions.githubusercontent.com:sub" && length(c.values) == 1 && contains(c.values, "repo:coursekata/ck-app-web:ref:refs/heads/main")
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

# A reader in GitHub's immutable subject form keeps its ids in the trust; the label alone names the
# role, so a repository moves to that form without a new role.
run "a_reader_in_the_immutable_form_keeps_its_role" {
  command = apply

  variables {
    release_readers = { datalake = { repository = "coursekata@12345678/ck-datalake@1098765432", branch = "main" } }
  }

  assert {
    condition     = aws_iam_role.this["release-read/datalake"].name == "ck-datalake-prd-image-release-read-datalake"
    error_message = "the immutable form names the same role as the plain form"
  }

  assert {
    condition = length([
      for c in one(data.aws_iam_policy_document.trust["release-read/datalake"].statement).condition : c
      if contains(c.values, "repo:coursekata@12345678/ck-datalake@1098765432:ref:refs/heads/main")
    ]) == 1
    error_message = "the trust keeps the subject exactly as GitHub writes it"
  }
}

run "no_readers_means_no_reader_roles" {
  command = apply

  assert {
    condition     = length([for k, _ in aws_iam_role.this : k if startswith(k, "release-read/")]) == 0 && length(output.release_read_role_arns) == 0
    error_message = "the three roles alone, as before"
  }
}

# A producer whose build consumes another producer's release as a build context: its builds, on a
# pull request and on the default branch, may pull that release and nothing else of the sibling's.
run "builds_may_pull_a_sibling_release_and_nothing_else_may" {
  command = apply

  variables {
    release_readers                 = { datalake = { repository = "coursekata/ck-datalake", branch = "main" } }
    sibling_release_repository_arns = ["arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-contract-release"]
  }

  assert {
    condition = alltrue([for k in ["candidate", "cache-read"] : contains(one([
      for s in data.aws_iam_policy_document.permissions[k].statement : s.resources if s.sid == "Read"
    ]), "arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-contract-release")])
    error_message = "the candidate and cache-read roles read the sibling's release repository"
  }

  assert {
    condition = alltrue([for k in ["release", "release-read/datalake"] : !contains(one([
      for s in data.aws_iam_policy_document.permissions[k].statement : s.resources if s.sid == "Read"
    ]), "arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-contract-release")])
    error_message = "the release role and a reader get nothing from the sibling"
  }

  assert {
    condition = alltrue([for k in keys(aws_iam_role.this) : alltrue([
      for s in data.aws_iam_policy_document.permissions[k].statement :
      s.sid != "Write" || !contains(s.resources, "arn:aws:ecr:us-west-2:903709589067:repository/ck-datalake-prd-contract-release")
    ])])
    error_message = "no role may write the sibling's repository"
  }

  assert {
    condition = alltrue([for k in keys(aws_iam_role.this) : anytrue([
      for s in data.aws_iam_policy_document.permissions[k].statement :
      s.effect == "Deny" && length(s.resources) == 3
    ])])
    error_message = "the deny still names this producer's own three repositories and nothing else"
  }
}
