locals {
  stage_label_values = {
    name       = coalesce(var.stage_name, var.name)
    attributes = var.stage_attributes
  }
  publish_label_values = {
    name       = coalesce(var.publish_name, var.name)
    attributes = var.publish_attributes
  }

  image_write_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:CompleteLayerUpload",
    "ecr:DescribeImages",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]
  image_read_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:DescribeImages",
    "ecr:GetDownloadUrlForLayer",
  ]
  image_mutate_actions = [
    "ecr:BatchDeleteImage",
    "ecr:CompleteLayerUpload",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]
}

data "context_label" "stage" {
  values = local.stage_label_values
}

data "context_tags" "stage" {
  values = local.stage_label_values
}

data "context_label" "publish" {
  values = local.publish_label_values
}

data "context_tags" "publish" {
  values = local.publish_label_values
}

data "aws_iam_policy_document" "stage_trust" {
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
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "stage" {
  name               = data.context_label.stage.rendered
  assume_role_policy = data.aws_iam_policy_document.stage_trust.json
  tags               = data.context_tags.stage.tags
}

data "aws_iam_policy_document" "stage" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPushCandidates"
    effect    = "Allow"
    actions   = local.image_write_actions
    resources = [var.candidate_repository_arn]
  }

  statement {
    sid       = "EcrReadReleases"
    effect    = "Allow"
    actions   = ["ecr:DescribeImages"]
    resources = [var.release_repository_arn]
  }
}

resource "aws_iam_role_policy" "stage" {
  name   = "${aws_iam_role.stage.name}-${var.stage_policy_suffix}"
  role   = aws_iam_role.stage.id
  policy = data.aws_iam_policy_document.stage.json
}

data "aws_iam_policy_document" "publish_trust" {
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
      values   = ["repo:${var.github_repository}:ref:${var.publish_ref}"]
    }
  }
}

resource "aws_iam_role" "publish" {
  name               = data.context_label.publish.rendered
  assume_role_policy = data.aws_iam_policy_document.publish_trust.json
  tags               = data.context_tags.publish.tags
}

data "aws_iam_policy_document" "publish" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPushReleases"
    effect    = "Allow"
    actions   = local.image_write_actions
    resources = [var.release_repository_arn]
  }

  statement {
    sid       = "EcrReadCandidates"
    effect    = "Allow"
    actions   = local.image_read_actions
    resources = [var.candidate_repository_arn]
  }
}

resource "aws_iam_role_policy" "publish" {
  name   = "${aws_iam_role.publish.name}-${var.publish_policy_suffix}"
  role   = aws_iam_role.publish.id
  policy = data.aws_iam_policy_document.publish.json
}
