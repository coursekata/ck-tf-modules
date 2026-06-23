# A CloudWatch Logs log group primitive. It renders its name + tags from the org context provider in
# the canonical order, prepends an optional AWS-mandated source prefix (/aws/lambda/, /aws/ecs/,
# /aws/cloudtrail/ …), and applies a chosen retention. Centralizing the naming/tagging/retention
# convention here keeps every log group across the org consistent in one place instead of each module
# hand-rolling its own. Encryption defaults to AWS-managed; pass kms_key_arn to use a customer CMK.

# Name + tags from the context provider, canonical order. environment/surface render only when the
# consuming root (or a call-time override) populates them, and drop out otherwise — so a single-env
# group (foundation) and a multi-env one (datalake tiers) both render byte-identically to a
# hand-rolled label. `attributes` is omitted from the rendered id when empty.
data "context_label" "this" {
  properties = var.attributes == "" ? ["namespace", "domain", "environment", "surface", "name"] : ["namespace", "domain", "environment", "surface", "name", "attributes"]
  values     = local.label_values
}

data "context_tags" "this" {
  values = local.label_values
}

locals {
  # Slot values shared by the rendered name and the tags. environment/surface are call-time overrides
  # included ONLY when set, so a single-env consumer leaves them to the provider (empty) and a
  # multi-env one passes them per group.
  label_values = merge(
    { name = var.name, attributes = var.attributes },
    var.environment != "" ? { environment = var.environment } : {},
    var.surface != "" ? { surface = var.surface } : {},
  )

  # AWS mandates a /aws/<service>/ prefix for some sources (Lambda -> /aws/lambda/, ECS -> /aws/ecs/);
  # CloudTrail mirrors conventionally use /aws/cloudtrail/. The prefix is prepended to the
  # context-rendered id; "" leaves the bare rendered name.
  log_group_name = "${var.name_prefix}${data.context_label.this.rendered}"
}

# trivy:ignore:AVD-AWS-0017 The default AWS-managed key is the proportional encryption posture for
# operational + audit-mirror log groups, and matches the org's SSE-S3 system-of-record (the durable
# record's integrity comes from S3 Object Lock, not a CMK). A caller that needs a customer key passes
# kms_key_arn, which sets kms_key_id and makes this finding inapplicable.
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = data.context_tags.this.tags
}
