locals {
  label_values = {
    name       = var.name
    attributes = var.attributes
  }

  image_publish_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:CompleteLayerUpload",
    "ecr:DescribeImages",
    "ecr:GetDownloadUrlForLayer",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]
}

data "context_label" "this" {
  values = local.label_values
}

data "context_tags" "this" {
  values = local.label_values
}

data "aws_iam_policy_document" "trust" {
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

resource "aws_iam_role" "this" {
  name               = data.context_label.this.rendered
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = data.context_tags.this.tags
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPublish"
    effect    = "Allow"
    actions   = local.image_publish_actions
    resources = [var.repository_arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${aws_iam_role.this.name}-${var.policy_suffix}"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}
