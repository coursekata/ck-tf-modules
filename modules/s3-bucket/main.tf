# A hardened, durable S3 bucket primitive for org security/audit buckets (CloudTrail archive,
# Config delivery, …). Always-on baseline: public access fully blocked, TLS-only by default,
# versioning, SSE. Optional: Object Lock default retention, lifecycle expiry, SSE-KMS, and
# service-delivery grants merged into the bucket policy (see var.grants).
#
# This is NOT ck-datalake's tier-bucket (that archetype is ephemeral: always-KMS, versioning
# off, no Object Lock). Different trust/retention model — do not conflate.

# Partition (aws / aws-us-gov / aws-cn) for building the bucket ARN; logical, no API call.
data "aws_partition" "current" {}

# Name + tags from the context provider, in the org canonical order. environment + surface render
# only when the consuming root populates them (e.g. ck-datalake tier buckets:
# ck-datalake-stg-raw-app); they drop out for single-env audit buckets (ck-org-cloudtrail-logs).
# `attributes` is omitted from the rendered id when empty.
data "context_label" "this" {
  properties = var.attributes == "" ? ["namespace", "domain", "environment", "surface", "name"] : ["namespace", "domain", "environment", "surface", "name", "attributes"]
  values     = local.label_values
}

data "context_tags" "this" {
  values = local.label_values
}

locals {
  # Slot values shared by the label (name) and the tags. environment/surface are call-time
  # overrides included ONLY when set, so a single-env consumer (foundation/tooling) leaves them to
  # the provider (empty) and stays byte-identical, while a datalake tier passes them per bucket.
  label_values = merge(
    { name = var.name, attributes = var.attributes },
    var.environment != "" ? { environment = var.environment } : {},
    var.surface != "" ? { surface = var.surface } : {},
  )

  object_lock_enabled = var.object_lock != null

  # SSE-KMS either with a created CMK (create_kms) or a passed-in key (kms_key_arn); the two are
  # mutually exclusive (validated). local.kms_key_arn is the effective key, null for SSE-S3.
  use_kms     = var.create_kms || var.kms_key_arn != null
  kms_key_arn = var.create_kms ? one(aws_kms_key.this[*].arn) : var.kms_key_arn

  has_lifecycle = var.lifecycle_rule != null && anytrue([
    try(var.lifecycle_rule.expiration_days, null) != null,
    try(var.lifecycle_rule.noncurrent_version_expiration_days, null) != null,
    try(var.lifecycle_rule.abort_incomplete_multipart_days, null) != null,
  ])
  build_policy = var.tls_only || length(var.grants) > 0 || var.require_sse_kms

  # The bucket's own ARN, built from the SAME rendered name the bucket is created with. An S3 ARN
  # is always arn:<partition>:s3:::<name>, so this equals aws_s3_bucket.this.arn — but it is known
  # at plan (the resource attribute is not), which keeps the whole policy determinable at plan and
  # means a grant never has to carry a bucket reference.
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${data.context_label.this.rendered}"
}

# Server access logging is intentionally omitted — data-plane auditing is expected to come from
# a separate CloudTrail/data-events trail, not per-bucket logs. SSE-S3 is the default; pass
# kms_key_arn for SSE-KMS.
# trivy:ignore:AVD-AWS-0089
# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "this" {
  bucket              = data.context_label.this.rendered
  object_lock_enabled = local.object_lock_enabled

  # context_tags emits Name = the bare `name` slot; pin it to the full rendered id (the AWS
  # console convention). Owner/Repo/ManagedBy come from the root provider's default_tags.
  tags = merge(data.context_tags.this.tags, { Name = data.context_label.this.rendered })

  lifecycle {
    precondition {
      condition     = var.object_lock == null || var.versioning_enabled
      error_message = "Object Lock requires versioning_enabled = true."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs (BucketOwnerEnforced) by default. Nullable so an import baseline can leave
# ownership unmanaged when the existing bucket has no explicit ownership-controls config.
resource "aws_s3_bucket_ownership_controls" "this" {
  count  = var.object_ownership != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Optional dedicated CMK (create_kms). Annual rotation, 30-day deletion window. The key POLICY is
# intentionally NOT set here — the bucket gets AWS's default root key policy, and the caller may
# attach an aws_kms_key_policy (via the kms_key_id/kms_key_arn outputs) to grant concrete principal
# ARNs (e.g. a data-export role), keeping this module a pure storage primitive.
resource "aws_kms_key" "this" {
  count = var.create_kms ? 1 : 0

  description             = "CMK for ${data.context_label.this.rendered}."
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = data.context_tags.this.tags
}

resource "aws_kms_alias" "this" {
  count = var.create_kms ? 1 : 0

  name          = "alias/${data.context_label.this.rendered}"
  target_key_id = aws_kms_key.this[0].id
}

# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = local.use_kms
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count  = local.object_lock_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode  = var.object_lock.mode
      years = try(var.object_lock.retention_years, null)
      days  = try(var.object_lock.retention_days, null)
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = local.has_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "retention"
    status = "Enabled"

    # Empty prefix ("") is the bucket-wide filter (the default). A non-empty expiration_prefix
    # scopes expiry to one key prefix — e.g. a tier that expires only "_athena-results/" while
    # leaving table data alone.
    filter {
      prefix = try(var.lifecycle_rule.expiration_prefix, "")
    }

    dynamic "expiration" {
      for_each = try(var.lifecycle_rule.expiration_days, null) != null ? [1] : []
      content {
        days = var.lifecycle_rule.expiration_days
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = try(var.lifecycle_rule.noncurrent_version_expiration_days, null) != null ? [1] : []
      content {
        noncurrent_days = var.lifecycle_rule.noncurrent_version_expiration_days
      }
    }

    dynamic "abort_incomplete_multipart_upload" {
      for_each = try(var.lifecycle_rule.abort_incomplete_multipart_days, null) != null ? [1] : []
      content {
        days_after_initiation = var.lifecycle_rule.abort_incomplete_multipart_days
      }
    }
  }
}

# The bucket's single policy: the optional TLS-only deny plus one Allow per grant. Each grant's
# resources are built HERE from the bucket's OWN ARN (so a grant carries no bucket reference and
# its producer stays decoupled). A bucket may have only one policy; semantically-equal policies
# import to no-diff via the provider's policy-equivalence check.
data "aws_iam_policy_document" "this" {
  count = local.build_policy ? 1 : 0

  dynamic "statement" {
    for_each = var.tls_only ? [1] : []
    content {
      sid       = "DenyInsecureTransport"
      effect    = "Deny"
      actions   = ["s3:*"]
      resources = [local.bucket_arn, "${local.bucket_arn}/*"]

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

  # One Allow statement per grant; the bucket ARN is injected into each resource (key_suffix
  # "" -> the bucket itself; "/AWSLogs/<acct>/*" -> an object path).
  dynamic "statement" {
    for_each = { for g in var.grants : g.sid => g }
    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = [for ks in statement.value.key_suffixes : ks == "" ? local.bucket_arn : "${local.bucket_arn}${ks}"]

      # Exactly one principal per grant (validated): an AWS principal ARN, else a Service principal.
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

  # Optional encryption invariant (require_sse_kms): refuse any PutObject not SSE-KMS-encrypted with
  # THIS bucket's CMK. StringNotEqualsIfExists denies a header-less upload too (an absent header
  # satisfies the != test) — so every writer must send the SSE-KMS headers explicitly. Inert
  # without a CMK (the require_sse_kms validation guarantees one).
  dynamic "statement" {
    for_each = var.require_sse_kms ? [1] : []
    content {
      sid       = "DenyNonKmsUploads"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["aws:kms"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.require_sse_kms ? [1] : []
    content {
      sid       = "DenyWrongKmsKey"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [local.kms_key_arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = local.build_policy ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this[0].json

  # Ensure the public-access-block is in place before a policy is attached, so a fresh
  # apply can't momentarily trip block_public_policy evaluation.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
