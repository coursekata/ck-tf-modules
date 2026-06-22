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
}
