locals {
  areas = ["candidate", "release", "cache"]

  # One candidate, release and cache repository per image, keyed <image>/<area>.
  repositories = {
    for pair in setproduct(var.images, local.areas) :
    "${pair[0]}/${pair[1]}" => { image = pair[0], area = pair[1] }
  }

  # A candidate lives until its run's release, which a re-run can repeat for up to
  # 30 days. A cache a later release replaced keeps no tag and expires 7 days after
  # its push, not its replacement. Builds import the tagged cache, which never
  # expires, and released images never expire, since a deployment may still name
  # their digest.
  expire_after_days = { candidate = 30, cache = 7 }

  # One release-read role per consumer repository, keyed release-read/<repository>, trusted on the
  # branch the consumer names, which need not be the producer's.
  readers = { for r, b in var.release_readers : "release-read/${r}" => { repository = r, branch = b } }

  subjects = merge({
    candidate    = "repo:${var.github_repository}:ref:refs/heads/${var.default_branch}"
    "cache-read" = "repo:${var.github_repository}:pull_request"
    release      = "repo:${var.github_repository}:environment:release"
  }, { for key, x in local.readers : key => "repo:${x.repository}:ref:refs/heads/${x.branch}" })

  # The label's attributes slot takes only [a-z0-9-], and IAM allows 64 characters in a role name.
  # A reader's name drops the immutable form's ids, so the role survives a move to that form, and
  # renders the rest in lowercase with every other character as a hyphen. The role's preconditions
  # refuse a name that is too long or that two readers share.
  role_attributes = merge(
    { candidate = "candidate", "cache-read" = "cache-read", release = "release" },
    { for key, x in local.readers : key => "release-read-${replace(lower(replace(x.repository, "/@[0-9]+/", "")), "/[^a-z0-9]+/", "-")}" },
  )

  pull_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:DescribeImages",
    "ecr:GetDownloadUrlForLayer",
    "ecr:ListImages",
  ]

  push_actions = [
    "ecr:CompleteLayerUpload",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]

  # No role may remove what the pipeline wrote or loosen the repositories that hold
  # it. Expiry belongs to the lifecycle policies alone.
  denied_actions = [
    "ecr:BatchDeleteImage",
    "ecr:DeleteLifecyclePolicy",
    "ecr:DeleteRepository",
    "ecr:DeleteRepositoryPolicy",
    "ecr:PutImageTagMutability",
    "ecr:PutLifecyclePolicy",
    "ecr:SetRepositoryPolicy",
  ]

  repository_names = merge(
    { for key, repo in aws_ecr_repository.this : key => repo.name },
    { for key, repo in aws_ecr_repository.cache : key => repo.name },
  )

  # Built from each repository's name rather than read back from the repository, so
  # each role's policy is known at plan time and names exactly its repositories.
  repository_arns = {
    for key, name in local.repository_names : key => join(":", [
      "arn", data.aws_partition.current.partition, "ecr", data.aws_region.current.region,
      data.aws_caller_identity.current.account_id, "repository/${name}",
    ])
  }

  arns = {
    for area in local.areas : area => [
      for key, arn in local.repository_arns : arn if local.repositories[key].area == area
    ]
  }

  # A default-branch build pushes candidates and reads the release cache. A pull
  # request reads the release cache and nothing else. The release job reads
  # candidates and writes releases and caches. A consumer's reader reads releases
  # and nothing else.
  writes = merge({
    candidate    = local.arns.candidate
    "cache-read" = []
    release      = concat(local.arns.release, local.arns.cache)
  }, { for key, _ in local.readers : key => [] })
  reads = merge({
    candidate    = local.arns.cache
    "cache-read" = local.arns.cache
    release      = local.arns.candidate
  }, { for key, _ in local.readers : key => local.arns.release })
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "context_label" "repository" {
  for_each = local.repositories
  values   = { name = each.value.image, attributes = "image-${each.value.area}" }
}

data "context_tags" "repository" {
  for_each = local.repositories
  values   = { name = each.value.image, attributes = "image-${each.value.area}" }
}

# trivy:ignore:AVD-AWS-0033 # AES-256 is sufficient for image bytes
resource "aws_ecr_repository" "this" {
  for_each = { for key, repo in local.repositories : key => repo if repo.area != "cache" }

  name                 = data.context_label.repository[each.key].rendered
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = data.context_tags.repository[each.key].tags
}

# Each release moves the cache tag to its own cache, so these tags are mutable.
# Only the release role writes this repository.
# trivy:ignore:AVD-AWS-0031 # the cache tag must move, and only the release role can move it
# trivy:ignore:AVD-AWS-0033 # AES-256 is sufficient for image bytes
resource "aws_ecr_repository" "cache" {
  for_each = { for key, repo in local.repositories : key => repo if repo.area == "cache" }

  name                 = data.context_label.repository[each.key].rendered
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = data.context_tags.repository[each.key].tags
}

resource "aws_ecr_lifecycle_policy" "candidate" {
  for_each = { for key, repo in local.repositories : key => repo if repo.area == "candidate" }

  repository = aws_ecr_repository.this[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire candidate images and caches ${local.expire_after_days.candidate} days after push"
      selection = {
        tagStatus   = "any"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = local.expire_after_days.candidate
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "cache" {
  for_each = aws_ecr_repository.cache

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged caches ${local.expire_after_days.cache} days after push"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = local.expire_after_days.cache
      }
      action = { type = "expire" }
    }]
  })
}

data "context_label" "role" {
  for_each = local.subjects
  values   = { name = "image", attributes = local.role_attributes[each.key] }
}

data "context_tags" "role" {
  for_each = local.subjects
  values   = { name = "image", attributes = local.role_attributes[each.key] }
}

data "aws_iam_policy_document" "trust" {
  for_each = local.subjects

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.subjects

  name               = data.context_label.role[each.key].rendered
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json
  tags               = data.context_tags.role[each.key].tags

  lifecycle {
    precondition {
      condition     = length(data.context_label.role[each.key].rendered) <= 64
      error_message = "The role name ${data.context_label.role[each.key].rendered} is longer than the 64 characters IAM allows. Shorten the reader in release_readers, or the context that names the roles."
    }
    precondition {
      condition     = length(distinct([for l in data.context_label.role : l.rendered])) == length(data.context_label.role)
      error_message = "Two entries in release_readers render the same role name; readers that differ only in case, dots or separators collide."
    }
  }
}

data "aws_iam_policy_document" "permissions" {
  for_each = local.subjects

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(local.writes[each.key]) > 0 ? [local.writes[each.key]] : []
    content {
      sid       = "Write"
      effect    = "Allow"
      actions   = concat(local.pull_actions, local.push_actions)
      resources = statement.value
    }
  }

  statement {
    sid       = "Read"
    effect    = "Allow"
    actions   = local.pull_actions
    resources = local.reads[each.key]
  }

  statement {
    sid       = "NeverDeleteOrLoosen"
    effect    = "Deny"
    actions   = local.denied_actions
    resources = values(local.repository_arns)
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = local.subjects

  name   = "${aws_iam_role.this[each.key].name}-ecr"
  role   = aws_iam_role.this[each.key].id
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
