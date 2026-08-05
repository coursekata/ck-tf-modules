# Proves the grants seam: each grant becomes one Allow statement with the bucket's OWN ARN
# injected into its resources. The real aws provider runs OFFLINE (skip_*) so
# aws_iam_policy_document actually renders — it is mocked (hence unassertable) under
# mock_provider. The bucket ARN is built from the rendered name (local.bucket_arn), known at
# plan, so the rendered policy JSON is assertable without overriding any resource.

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
  values = { namespace = "ck", domain = "org" }
}

run "grants_inject_the_bucket_arn_into_the_policy" {
  command = plan

  variables {
    name       = "cloudtrail"
    attributes = "logs"
    tls_only   = true
    grants = [
      {
        sid               = "AWSCloudTrailAclCheck"
        principal_service = "cloudtrail.amazonaws.com"
        actions           = ["s3:GetBucketAcl"]
        key_suffixes      = [""]
        conditions = [
          { test = "StringEquals", variable = "aws:SourceArn", values = ["arn:aws:cloudtrail:us-west-2:442557178688:trail/ck-org-cloudtrail"] },
        ]
      },
      {
        sid               = "AWSCloudTrailWrite"
        principal_service = "cloudtrail.amazonaws.com"
        actions           = ["s3:PutObject"]
        key_suffixes      = ["/AWSLogs/442557178688/*", "/AWSLogs/o-fblpx76hzw/*"]
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceArn", values = ["arn:aws:cloudtrail:us-west-2:442557178688:trail/ck-org-cloudtrail"] },
        ]
      },
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "a policy must exist when grants are supplied"
  }

  # The bucket's OWN ARN is injected into each grant's resources (the whole point of the seam).
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "arn:aws:s3:::ck-org-cloudtrail-logs/AWSLogs/442557178688/*")
    error_message = "Write grant must target bucket-ARN + the management-account AWSLogs path"
  }
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "arn:aws:s3:::ck-org-cloudtrail-logs/AWSLogs/o-fblpx76hzw/*")
    error_message = "Write grant must also target bucket-ARN + the org-id AWSLogs path"
  }
  # The bare key_suffix ("") yields the bucket ARN itself (no object suffix) for the ACL check.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "\"arn:aws:s3:::ck-org-cloudtrail-logs\"")
    error_message = "AclCheck grant (key_suffix \"\") must target the bare bucket ARN"
  }
  # Principal + the fiddly conditions render.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "cloudtrail.amazonaws.com")
    error_message = "grant must name the CloudTrail service principal"
  }
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "trail/ck-org-cloudtrail") && strcontains(data.aws_iam_policy_document.this[0].json, "bucket-owner-full-control")
    error_message = "grant conditions (SourceArn + x-amz-acl) must render"
  }
  # The tls-only deny coexists in the single merged policy.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.this[0].json, "DenyInsecureTransport")
    error_message = "the tls-only deny must remain alongside the grants"
  }
  # policy_json carries the same rendered policy out to consumers, so a root can assert the scope
  # of its own grants. Checked by decoding rather than by string match, because a consumer asserts
  # against the parsed document.
  assert {
    condition     = contains([for s in jsondecode(output.policy_json).Statement : s.Sid], "AWSCloudTrailWrite")
    error_message = "policy_json must expose the rendered policy, including each grant's statement"
  }
}

# bucket_name_override: adopt a pre-existing externally-named bucket (the app's cross-account
# write case — a legacy asset bucket the mgmt account writes into). The literal name is used, the
# policy targets THAT bucket's ARN, and the slot tags still classify it.
run "bucket_name_override_adopts_a_legacy_bucket" {
  command = plan

  variables {
    name                 = "assets"            # classification only — drives the slot tags
    bucket_name_override = "coursekata-assets" # the literal externally-referenced legacy name
    tls_only             = true
    grants = [
      {
        sid           = "SourceAccountWrite"
        principal_aws = "arn:aws:iam::442557178688:root"
        actions       = ["s3:PutObject", "s3:PutObjectTagging"]
        key_suffixes  = ["/*"]
      },
    ]
  }

  # The bucket takes the literal override, NOT the convention id (ck-org-assets).
  assert {
    condition     = aws_s3_bucket.this.bucket == "coursekata-assets"
    error_message = "bucket_name_override must set the literal bucket name"
  }
  # Name tag follows the bucket; the slot tags still classify it (Domain=org from the provider).
  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "coursekata-assets" && aws_s3_bucket.this.tags["Domain"] == "org"
    error_message = "Name tag = the override; slot tags still come from context"
  }
  # The TLS-only deny + the cross-account grant target the OVERRIDE bucket's ARN, not the convention id.
  assert {
    condition = (
      strcontains(data.aws_iam_policy_document.this[0].json, "arn:aws:s3:::coursekata-assets") &&
      !strcontains(data.aws_iam_policy_document.this[0].json, "ck-org-assets") &&
      strcontains(data.aws_iam_policy_document.this[0].json, "arn:aws:iam::442557178688:root")
    )
    error_message = "the policy must target the override ARN and grant the source-account principal"
  }
}
