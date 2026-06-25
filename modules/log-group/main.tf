# A CloudWatch Logs log group primitive: a context-rendered name (with an optional AWS-mandated
# source prefix) + tags, and a caller-chosen retention. Encryption defaults to AWS-managed.
#
# Name + tags come from context.tf (data.context_label.this / data.context_tags.this).

locals {
  # AWS mandates a /aws/<service>/ prefix for some sources (Lambda, ECS); "" leaves the bare id.
  log_group_name = "${var.name_prefix}${data.context_label.this.rendered}"
}

# trivy:ignore:AVD-AWS-0017 AWS-managed encryption is the proportional posture for operational +
# audit-mirror groups, matching the org's SSE-S3 system-of-record; pass kms_key_arn for a CMK.
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = data.context_tags.this.tags
}
