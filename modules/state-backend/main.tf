# Reusable state-backend: an S3 bucket hardened to back an OpenTofu root's state via the
# 1.11+ native S3 lockfile (`use_lockfile = true` in the consumer's backend.tf — no
# DynamoDB table). The consuming root supplies the provider (and its default_tags); this
# module configures none. (The wrong-account guard is the root's job — every root calls the shared
# account-guard module as its preamble — so this module no longer takes an expected_account_id.)

# Bucket name + tags come from the cloudposse/context PROVIDER, configured by the consuming
# root with the org policy (required namespace, property order) and this repo's namespace/
# tenant. The module just adds name = "tfstate" (the bucket is always <...>-tfstate) and pins
# the state-bucket property order here, so a root's pipeline order can't rename the state
# bucket — only the slot VALUES (namespace/tenant/stage) inherit from the provider.
data "context_label" "this" {
  properties = ["namespace", "tenant", "stage", "name"]
  values     = { name = "tfstate" }
}

data "context_tags" "this" {
  values = { name = "tfstate" }
}

# Construct the bucket ARN from its (plan-known) name rather than referencing
# aws_s3_bucket.tfstate.arn, so the TLS policy document resolves fully at plan time (no
# apply-time deferral) and stays unit-testable. S3 ARNs carry no account/region segment.
data "aws_partition" "current" {}

locals {
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${data.context_label.this.rendered}"
}

# SSE-S3 (AES256) is sufficient for tfstate; a CMK would add key-management burden without
# commensurate benefit. Server access logging is intentionally omitted — the org CloudTrail
# trail covers data-plane auditing for these accounts.
# trivy:ignore:AVD-AWS-0089
# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "tfstate" {
  bucket = data.context_label.this.rendered

  # context_tags sets Name to the `name` value ("tfstate"); pin it to the full id instead —
  # the useful AWS convention (and what null-label did), so the Name tag is the bucket's name.
  tags = merge(data.context_tags.this.tags, { Name = data.context_label.this.rendered })
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tls_only.json
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-${var.noncurrent_version_expiration_days}d"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}
