# The v0.4.1 datalake tier-bucket archetype: per-call env/surface slots, optional CMK creation,
# SSE-KMS upload-pinning Denies, AWS-principal grants, and prefix-scoped lifecycle. The real aws
# provider runs OFFLINE (skip_*) so aws_iam_policy_document actually renders for the policy-content
# assertions (it is mocked/unassertable under mock_provider). Configured as a ck-datalake root would:
# domain=datalake at the provider, env/surface passed per bucket.

provider "aws" {
  region                      = "us-west-2"
  access_key                  = "testing"
  secret_key                  = "testing"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "context" {
  property_order  = ["namespace", "domain", "environment", "surface", "name", "attributes"]
  tags_value_case = "lower"
  properties = {
    namespace   = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    domain      = { validation_regex = "^[a-z0-9-]*$" }
    environment = { validation_regex = "^[a-z0-9-]*$" }
    surface     = { validation_regex = "^[a-z0-9-]*$" }
    name        = { validation_regex = "^[a-z0-9-]*$" }
    attributes  = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = { namespace = "ck", domain = "datalake" }
}

# --- RAW tier: create_kms + ephemeral shape (versioning off, prefix-less 7d expiry) ---
run "raw_tier_creates_its_cmk" {
  command = plan

  variables {
    name               = "app"
    environment        = "stg"
    surface            = "raw"
    create_kms         = true
    versioning_enabled = false
    tls_only           = true
    lifecycle_rule     = { expiration_days = 7 }
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-raw-app"
    error_message = "raw tier must render ck-datalake-stg-raw-app (env + surface per-call)"
  }
  # A dedicated CMK + alias is created and the bucket encrypts with it.
  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation == true
    error_message = "create_kms must make exactly one rotating CMK"
  }
  assert {
    condition     = aws_kms_alias.this[0].name == "alias/ck-datalake-stg-raw-app"
    error_message = "the CMK alias must be alias/<rendered-id>"
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" && one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    error_message = "create_kms must drive SSE-KMS with bucket-key enabled"
  }
  # Ephemeral tier shape: versioning Suspended, single prefix-less expiry rule.
  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "tier buckets set versioning_enabled=false -> Suspended"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration).days == 7 && aws_s3_bucket_lifecycle_configuration.this[0].rule[0].filter[0].prefix == ""
    error_message = "raw expiry must be 7d, bucket-wide (empty prefix)"
  }
  # The created key feeds the SSE config (its ARN is known-after-apply, so the output is asserted
  # structurally here via the key resource; the wiring is a trivial one(...[*].arn) passthrough).
}

# --- require_sse_kms pins uploads to a PASSED key (known value -> policy JSON is assertable) ---
run "require_sse_kms_pins_uploads" {
  command = plan

  variables {
    name            = "app"
    environment     = "stg"
    surface         = "staging"
    kms_key_arn     = "arn:aws:kms:us-west-2:903709589067:key/00000000-0000-0000-0000-000000000000"
    require_sse_kms = true
    tls_only        = true
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-staging-app"
    error_message = "staging tier must render ck-datalake-stg-staging-app"
  }
  # Deny any PutObject that isn't SSE-KMS...
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "DenyNonKmsUploads") && strcontains(data.aws_iam_policy_document.this[0].json, "StringNotEqualsIfExists")
    error_message = "require_sse_kms must emit DenyNonKmsUploads with StringNotEqualsIfExists"
  }
  # ...and pin it to THIS bucket's key id.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "DenyWrongKmsKey") && strcontains(data.aws_iam_policy_document.this[0].json, "00000000-0000-0000-0000-000000000000")
    error_message = "require_sse_kms must pin DenyWrongKmsKey to the bucket's key"
  }
}

# --- AWS-principal grant renders the role ARN as an AWS principal (not a Service) ---
run "aws_principal_grant_renders" {
  command = plan

  variables {
    name        = "app"
    environment = "stg"
    surface     = "raw"
    create_kms  = true
    tls_only    = true
    grants = [
      {
        sid           = "SnapshotExportServiceObjectOps"
        principal_aws = "arn:aws:iam::903709589067:role/ck-datalake-stg-raw-app-export"
        actions       = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        key_suffixes  = ["/*"]
      },
    ]
  }

  assert {
    condition = (
      strcontains(data.aws_iam_policy_document.this[0].json, "arn:aws:iam::903709589067:role/ck-datalake-stg-raw-app-export") &&
      strcontains(data.aws_iam_policy_document.this[0].json, "\"AWS\"")
    )
    error_message = "an AWS-principal grant must render its role ARN under an AWS principal"
  }
}

# --- analytical tier: SSE-S3 + prefix-scoped expiry (only _athena-results/) ---
run "analytical_prefix_scoped_expiry" {
  command = plan

  variables {
    name               = "app"
    environment        = "stg"
    surface            = "analytical"
    create_kms         = false
    versioning_enabled = false
    lifecycle_rule     = { expiration_days = 14, expiration_prefix = "_athena-results/" }
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "analytical tier (no CMK) must be SSE-S3"
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].filter[0].prefix == "_athena-results/"
    error_message = "expiration_prefix must scope the lifecycle filter to _athena-results/"
  }
}

# --- validations ---
run "create_kms_and_kms_key_arn_is_rejected" {
  command = plan

  variables {
    name        = "app"
    create_kms  = true
    kms_key_arn = "arn:aws:kms:us-west-2:903709589067:key/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.create_kms]
}

run "require_sse_kms_without_a_cmk_is_rejected" {
  command = plan

  variables {
    name            = "app"
    require_sse_kms = true
  }

  expect_failures = [var.require_sse_kms]
}

run "grant_with_both_principals_is_rejected" {
  command = plan

  variables {
    name = "app"
    grants = [
      {
        sid               = "bad"
        principal_service = "cloudtrail.amazonaws.com"
        principal_aws     = "arn:aws:iam::903709589067:role/x"
        actions           = ["s3:PutObject"]
      },
    ]
  }

  expect_failures = [var.grants]
}

run "grant_with_no_principal_is_rejected" {
  command = plan

  variables {
    name = "app"
    grants = [
      {
        sid     = "bad"
        actions = ["s3:GetObject"]
      },
    ]
  }

  expect_failures = [var.grants]
}

# The actual raw-tier wiring: the bucket CREATES its CMK and pins uploads to it. The created key's
# ARN is known-after-apply, so the DenyWrongKmsKey content is unknown at plan (its content is
# asserted against a KNOWN key in require_sse_kms_pins_uploads); here we prove the combination
# plans together and that require_sse_kms ALONE builds the policy (tls_only off).
run "create_kms_with_require_sse_kms_builds_the_policy" {
  command = plan

  variables {
    name            = "app"
    environment     = "stg"
    surface         = "raw"
    create_kms      = true
    require_sse_kms = true
    tls_only        = false
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "require_sse_kms must build a bucket policy even without tls_only"
  }
  assert {
    condition     = length(aws_kms_key.this) == 1 && one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "create_kms + require_sse_kms must plan together: a CMK feeding SSE-KMS"
  }
}
