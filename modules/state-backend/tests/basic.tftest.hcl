# Unit tests for the state-backend module. No mock_provider: aws_iam_policy_document only
# renders under a real provider, so the suite runs the real aws provider OFFLINE (dummy
# creds + skipped configure-time STS calls). Every assertion is plan-time and structural —
# the TLS policy is resolvable at plan because the bucket ARN is constructed from the (known) name.

provider "aws" {
  region                      = "us-west-2"
  access_key                  = "testing"
  secret_key                  = "testing"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# The cloudposse/context provider supplies namespace/tenant/tags (the consuming root configures
# it in real life); property_order + required namespace mirror the org policy.
provider "context" {
  property_order  = ["namespace", "tenant", "stage", "name"]
  tags_value_case = "lower" # org invariant: lowercase tag values (Title-case keys are the default)
  properties = {
    # validation_regex enforces lowercase — the provider does NOT auto-lowercase the id, so this
    # is the guard against an invalid (uppercase) bucket name.
    namespace = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    tenant    = { validation_regex = "^[a-z0-9-]*$" }
    stage     = { validation_regex = "^[a-z0-9-]*$" }
    name      = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = {
    namespace = "ck"
    tenant    = "tooling"
  }
}

run "bucket_name_follows_label_convention" {
  command = plan

  assert {
    condition     = aws_s3_bucket.tfstate.bucket == "ck-tooling-tfstate"
    error_message = "bucket name must be <namespace>-<tenant>-tfstate"
  }
  # Name tag is the full id (not the bare "tfstate" name) — matches the prior null-label
  # convention, so switching a live bucket to the provider is a no-op.
  assert {
    condition     = aws_s3_bucket.tfstate.tags["Name"] == "ck-tooling-tfstate"
    error_message = "Name tag must be the full bucket id, not the bare name value"
  }
  # Lock the tag-key contract the ck-tooling no-op depends on: Namespace/Tenant present + exact.
  assert {
    condition     = aws_s3_bucket.tfstate.tags["Namespace"] == "ck"
    error_message = "Namespace tag must be present and equal ck"
  }
  assert {
    condition     = aws_s3_bucket.tfstate.tags["Tenant"] == "tooling"
    error_message = "Tenant tag must be present and equal tooling"
  }
}

run "hardening_is_enforced" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.tfstate.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be enabled so state history is recoverable"
  }
  # All four public-access-block controls must be on — partial PAB is a silent exposure.
  assert {
    condition = (
      aws_s3_bucket_public_access_block.tfstate.block_public_acls &&
      aws_s3_bucket_public_access_block.tfstate.block_public_policy &&
      aws_s3_bucket_public_access_block.tfstate.ignore_public_acls &&
      aws_s3_bucket_public_access_block.tfstate.restrict_public_buckets
    )
    error_message = "all four public-access-block controls must be enabled"
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.tfstate.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "bucket must default to SSE-S3 (AES256) encryption"
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.tfstate.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "default noncurrent-version expiry must be 90 days"
  }
}

run "tls_only_bucket_policy_denies_insecure_transport" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.tls_only.json).Statement[0].Effect == "Deny"
    error_message = "bucket policy statement must Deny"
  }
  assert {
    condition     = jsondecode(data.aws_iam_policy_document.tls_only.json).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "bucket policy must trigger when aws:SecureTransport is false (TLS-only)"
  }
  # The policy must scope to the bucket and its objects, never a wildcard resource.
  assert {
    condition = (
      contains(jsondecode(data.aws_iam_policy_document.tls_only.json).Statement[0].Resource, "arn:aws:s3:::ck-tooling-tfstate") &&
      !contains(jsondecode(data.aws_iam_policy_document.tls_only.json).Statement[0].Resource, "*")
    )
    error_message = "bucket policy must target the bucket ARN, not a wildcard resource"
  }
}

run "noncurrent_expiry_is_configurable" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 30
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.tfstate.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "noncurrent expiry must honor the override"
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.tfstate.rule[0].id == "expire-noncurrent-30d"
    error_message = "lifecycle rule id must reflect the configured retention"
  }
}
