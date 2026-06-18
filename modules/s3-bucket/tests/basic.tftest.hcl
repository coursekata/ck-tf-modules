# Unit tests for the hardened s3-bucket primitive. mock_provider => no AWS calls; the bucket
# name is rendered from the context provider (configured below as a tenant=org root would), so
# each run names its bucket via the `name`/`attributes` slots. Assertions target config-derived
# attributes so the always-on hardening and the optional Object Lock / lifecycle / SSE /
# ownership behaviour are pinned against regression.
#
# Coverage note: the bucket-policy CONTENT (the TLS-only deny + the per-grant statements) is NOT
# asserted here — aws_iam_policy_document is mocked under mock_provider, so its JSON is
# unassertable in this harness. Grant/policy content is covered in grants.tftest.hcl (real
# provider, offline). Existence (count) is pinned below.

mock_provider "aws" {
  # aws_iam_policy_document is mocked here (its content is asserted in grants.tftest.hcl, not
  # here); return valid JSON so the aws_s3_bucket_policy resource's JSON validation passes.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

provider "context" {
  property_order  = ["namespace", "tenant", "stage", "name", "attributes"]
  tags_value_case = "lower"
  properties = {
    namespace  = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    tenant     = { validation_regex = "^[a-z0-9-]*$" }
    stage      = { validation_regex = "^[a-z0-9-]*$" }
    name       = { validation_regex = "^[a-z0-9-]*$" }
    attributes = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = { namespace = "ck", tenant = "org" }
}

# --- The CloudTrail archive shape: versioning + GOVERNANCE 3yr lock + AES256 + lifecycle ---
run "cloudtrail_archive_shape" {
  command = plan

  variables {
    name               = "cloudtrail"
    attributes         = "logs"
    versioning_enabled = true
    object_lock = {
      mode            = "GOVERNANCE"
      retention_years = 3
    }
    lifecycle_rule = {
      expiration_days                    = 1095
      noncurrent_version_expiration_days = 90
      abort_incomplete_multipart_days    = 7
    }
    tls_only = true
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-org-cloudtrail-logs"
    error_message = "the bucket name must render ck-org-cloudtrail-logs from the slots"
  }
  # Tags are rendered by the module: Name pinned to the full id, plus the slot tags.
  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "ck-org-cloudtrail-logs" && aws_s3_bucket.this.tags["Tenant"] == "org" && aws_s3_bucket.this.tags["Attributes"] == "logs"
    error_message = "tags must pin Name=full id and carry Tenant=org, Attributes=logs"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "all four public-access-block settings must be true"
  }
  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this[0].rule).object_ownership == "BucketOwnerEnforced"
    error_message = "object ownership must default to BucketOwnerEnforced (ACLs disabled)"
  }
  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled == true
    error_message = "object_lock_enabled must be true when object_lock is set"
  }
  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be Enabled"
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "default encryption must be AES256 (SSE-S3) when no kms_key_arn"
  }
  assert {
    condition     = one(one(aws_s3_bucket_object_lock_configuration.this[0].rule).default_retention).mode == "GOVERNANCE" && one(one(aws_s3_bucket_object_lock_configuration.this[0].rule).default_retention).years == 3
    error_message = "object lock must be GOVERNANCE / 3 years"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration).days == 1095
    error_message = "cloudtrail lifecycle must expire at 1095 days"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration).noncurrent_days == 90
    error_message = "cloudtrail lifecycle noncurrent expiration must be 90 days"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "cloudtrail lifecycle must abort incomplete MPUs after 7 days"
  }
  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "a bucket policy must exist when tls_only is true"
  }
}

# --- The Config-delivery shape: versioning + AES256, NO Object Lock, only a noncurrent rule ---
run "config_delivery_shape_no_object_lock" {
  command = plan

  variables {
    name               = "config"
    attributes         = "delivery"
    versioning_enabled = true
    object_lock        = null
    lifecycle_rule = {
      noncurrent_version_expiration_days = 365
    }
    tls_only = true
  }

  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled == false
    error_message = "object_lock_enabled must be false when object_lock is null"
  }
  assert {
    condition     = length(aws_s3_bucket_object_lock_configuration.this) == 0
    error_message = "no object lock configuration when object_lock is null"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration).noncurrent_days == 365
    error_message = "config-delivery noncurrent expiration must be 365 days"
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration) == 0
    error_message = "config-delivery lifecycle must NOT set an expiration"
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload) == 0
    error_message = "config-delivery lifecycle must NOT abort MPUs"
  }
}

# --- No lifecycle + no policy + no ownership: import-to-no-diff against a bare bucket ---
run "bare_bucket_omits_optional_resources" {
  command = plan

  variables {
    name             = "bare"
    lifecycle_rule   = null
    tls_only         = false
    object_ownership = null
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 0
    error_message = "no lifecycle configuration when lifecycle_rule is null"
  }
  assert {
    condition     = length(aws_s3_bucket_policy.this) == 0
    error_message = "no bucket policy when tls_only is false and no additional policy is given"
  }
  assert {
    condition     = length(aws_s3_bucket_ownership_controls.this) == 0
    error_message = "no ownership controls when object_ownership is null"
  }
}

# --- SSE-KMS path ---
run "kms_encryption" {
  command = plan

  variables {
    name        = "kms"
    kms_key_arn = "arn:aws:kms:us-west-2:232672477651:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "sse_algorithm must be aws:kms when kms_key_arn is set"
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    error_message = "bucket_key_enabled must be true for SSE-KMS"
  }
}

# --- COMPLIANCE mode + days-only retention (locks the validation fix for the days path) ---
run "compliance_mode_days_retention" {
  command = plan

  variables {
    name = "compliance"
    object_lock = {
      mode           = "COMPLIANCE"
      retention_days = 30
    }
  }

  assert {
    condition     = one(one(aws_s3_bucket_object_lock_configuration.this[0].rule).default_retention).mode == "COMPLIANCE"
    error_message = "object lock mode must be COMPLIANCE"
  }
  assert {
    condition     = one(one(aws_s3_bucket_object_lock_configuration.this[0].rule).default_retention).days == 30
    error_message = "object lock retention must be 30 days on the days-only path"
  }
}

# --- Suspended versioning path ---
run "versioning_suspended" {
  command = plan

  variables {
    name               = "suspended"
    versioning_enabled = false
    object_lock        = null
    lifecycle_rule     = null
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "versioning must be Suspended when versioning_enabled = false"
  }
}

# --- Wrong-account credential must fail at plan (the account-guard safety net) ---
run "wrong_account_is_rejected" {
  command = plan

  variables {
    name                = "wrongacct"
    expected_account_id = "999999999999"
    tls_only            = false
    object_ownership    = null
  }

  expect_failures = [
    aws_s3_bucket.this,
  ]
}

# --- object_lock with both retention_years and retention_days is rejected at input ---
run "object_lock_rejects_both_year_and_day_retention" {
  command = plan

  variables {
    name = "badlock"
    object_lock = {
      mode            = "GOVERNANCE"
      retention_years = 3
      retention_days  = 1095
    }
  }

  expect_failures = [
    var.object_lock,
  ]
}
