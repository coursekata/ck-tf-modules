# A customer-managed KMS key primitive: a context-rendered alias + tags, annual rotation, and a key
# policy of the always-on root-account administration statement plus a caller-supplied grants seam.
# One module so the CMK hardening baseline (rotation on, a bounded deletion window, a root-admin
# statement so the key is never orphaned) doesn't drift between the org's bespoke keys.
#
# Name + tags come from context.tf (data.context_label.this / data.context_tags.this).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  key_name    = data.context_label.this.rendered
  description = var.description != "" ? var.description : "CMK for ${local.key_name}."

  # The account root principal, derived from the account this key is created in — never hand-passed.
  # Known at plan, so the whole key policy is determinable at plan.
  root_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
}

data "aws_iam_policy_document" "this" {
  # Always on: root-account key administration. Without it the key can become unmanageable (a key
  # whose only grants are service Decrypt/Encrypt can't be re-policied), so AWS's guidance is to keep
  # the root-admin statement. IAM policies in the account then further scope who may administer it.
  statement {
    sid       = "EnableRootAccountKeyAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.root_arn]
    }
  }

  # One Allow per grant; a key policy's resource is the key itself, expressed as "*".
  dynamic "statement" {
    for_each = { for g in var.grants : g.sid => g }
    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = ["*"]

      # The grant's XOR validation guarantees exactly one principal is set, so coalesce skips the
      # null and lands on the one present; the type matches whichever it was.
      principals {
        type        = statement.value.principal_aws != null ? "AWS" : "Service"
        identifiers = [coalesce(statement.value.principal_aws, statement.value.principal_service)]
      }

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description             = local.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  policy                  = data.aws_iam_policy_document.this.json

  tags = data.context_tags.this.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.key_name}"
  target_key_id = aws_kms_key.this.key_id
}
