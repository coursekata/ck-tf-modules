# A KMS-encrypted SNS topic delivered to Slack via AWS Chatbot — the org's reusable notification
# primitive, generalized from the datalake etl-alerting stack (the alarms/EventBridge rules that
# PUBLISH stay with the caller; this owns the topic, its policy, and the Slack binding). Native
# Chatbot SNS subscription, no bespoke webhook Lambda; the channel is read-only-guardrailed.
#
# Name + tags come from context.tf (data.context_label.this / data.context_tags.this).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  topic_name = data.context_label.this.rendered

  # Derived from the account/region this topic lives in — never hand-passed.
  account_id = data.aws_caller_identity.current.account_id
  root_arn   = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"

  # The topic's own ARN, built from the SAME name the topic is created with. An SNS ARN is always
  # arn:<partition>:sns:<region>:<account>:<name>, so this equals aws_sns_topic.this.arn — but it is
  # known at PLAN (the resource attribute is not), which keeps the whole topic policy determinable at
  # plan (matching the s3-bucket convention) rather than perpetually diffing on an unknown resource.
  topic_arn = "arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.region}:${local.account_id}:${local.topic_name}"

  guardrail_policy_arns = coalesce(
    var.chatbot_guardrail_policy_arns,
    ["arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"],
  )
}

# ─── SNS topic + policy ────────────────────────────────────────────────

# trivy:ignore:AVD-AWS-0095 an unencrypted topic is opt-in only (allow_unencrypted, enforced by the
# precondition below): the default path requires a CMK, so this suppresses the module's own
# default-scan false positive — a caller can't reach the unencrypted branch by omission.
resource "aws_sns_topic" "this" {
  name              = local.topic_name
  kms_master_key_id = var.kms_key_arn
  tags              = data.context_tags.this.tags

  lifecycle {
    precondition {
      condition     = var.kms_key_arn != null || var.allow_unencrypted
      error_message = "the SNS topic needs a CMK: set kms_key_arn, or set allow_unencrypted = true to deliberately run an unencrypted topic (e.g. when a KMS grant to the Chatbot service-linked role isn't in place and encryption would drop delivery)."
    }
  }
}

data "aws_iam_policy_document" "topic" {
  # The topic-scoped management actions (the AWS-default topic-policy set). SNS rejects sns:* here —
  # its access policy only admits actions valid on a topic resource.
  statement {
    sid    = "AllowAccountRootAdministration"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:AddPermission",
      "sns:RemovePermission",
      "sns:DeleteTopic",
      "sns:Subscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:Publish",
    ]
    resources = [local.topic_arn]

    principals {
      type        = "AWS"
      identifiers = [local.root_arn]
    }
  }

  # One Publish grant per publisher; service publishers get an automatic confused-deputy guard.
  dynamic "statement" {
    for_each = { for p in var.publishers : p.sid => p }
    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [local.topic_arn]

      principals {
        type        = statement.value.principal_aws != null ? "AWS" : "Service"
        identifiers = [coalesce(statement.value.principal_aws, statement.value.principal_service)]
      }

      dynamic "condition" {
        for_each = concat(
          statement.value.principal_service != null ? [{
            test     = "StringEquals"
            variable = "aws:SourceAccount"
            values   = [local.account_id]
          }] : [],
          statement.value.conditions,
        )
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic.json
}

# ─── AWS Chatbot → Slack ───────────────────────────────────────────────
#
# The channel role is read-only-guardrailed — a Slack-issued AWS CLI cannot mutate resources. The
# workspace must be authorized once in this account's Chatbot console; until then the config applies
# cleanly but no messages deliver.

data "aws_iam_policy_document" "chatbot_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  name               = "${local.topic_name}-chatbot"
  assume_role_policy = data.aws_iam_policy_document.chatbot_trust.json
  tags               = data.context_tags.this.tags
}

resource "aws_iam_role_policy_attachment" "chatbot_resource_explorer" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSResourceExplorerReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "chatbot_cloudwatch" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "this" {
  configuration_name    = local.topic_name
  slack_team_id         = var.slack_workspace_id
  slack_channel_id      = var.slack_channel_id
  iam_role_arn          = aws_iam_role.chatbot.arn
  sns_topic_arns        = [aws_sns_topic.this.arn]
  guardrail_policy_arns = local.guardrail_policy_arns
  logging_level         = var.logging_level

  tags = data.context_tags.this.tags
}
