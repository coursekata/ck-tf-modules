# Offline plan tests for the kms primitive: the alias renders from context, the always-on
# root-account administration statement is present, a grant renders (service principal + its
# condition), and the input guards fire. The real aws provider runs OFFLINE so
# aws_iam_policy_document renders for the policy assertions; aws_caller_identity is stubbed via
# override_data (it would otherwise call STS).

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
  values = { namespace = "ck", domain = "cd" }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "883385860947"
  }
}

# A CD delivery CMK: domain=cd (provider) + environment/surface/name -> ck-cd-prd-datalake-lake.
run "alias_and_root_admin_render" {
  command = plan

  variables {
    environment = "prd"
    surface     = "datalake"
    name        = "lake"
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/ck-cd-prd-datalake-lake"
    error_message = "alias must render alias/ + the context id"
  }
  assert {
    condition     = strcontains(aws_kms_key.this.policy, "EnableRootAccountKeyAdministration") && strcontains(aws_kms_key.this.policy, "arn:aws:iam::883385860947:root")
    error_message = "key policy must always include the root-account administration statement for this account"
  }
  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true && aws_kms_key.this.deletion_window_in_days == 30
    error_message = "rotation on + 30-day deletion window are the defaults"
  }
}

run "grant_renders_service_statement" {
  command = plan

  variables {
    environment = "prd"
    surface     = "datalake"
    name        = "lake"
    grants = [{
      sid               = "AllowEventBridgeEncryptForSns"
      principal_service = "events.amazonaws.com"
      actions           = ["kms:GenerateDataKey*", "kms:Decrypt"]
      conditions = [{
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = ["883385860947"]
      }]
    }]
  }

  assert {
    condition     = strcontains(aws_kms_key.this.policy, "events.amazonaws.com") && strcontains(aws_kms_key.this.policy, "aws:SourceAccount")
    error_message = "a service grant must render its principal and condition into the key policy"
  }
}

run "reserved_sid_is_rejected" {
  command = plan

  variables {
    name = "x"
    grants = [{
      sid               = "EnableRootAccountKeyAdministration"
      principal_service = "events.amazonaws.com"
      actions           = ["kms:Decrypt"]
    }]
  }

  expect_failures = [var.grants]
}

run "both_principals_rejected" {
  command = plan

  variables {
    name = "x"
    grants = [{
      sid               = "Bad"
      principal_service = "events.amazonaws.com"
      principal_aws     = "arn:aws:iam::883385860947:role/x"
      actions           = ["kms:Decrypt"]
    }]
  }

  expect_failures = [var.grants]
}

# The AWS-principal branch of the grants seam: a role ARN must render under an "AWS" principal (not
# mislabeled Service), with its actions — the coalesce-lands-on-principal_aws path nothing else covers.
run "grant_renders_aws_principal_statement" {
  command = plan

  variables {
    environment = "prd"
    surface     = "datalake"
    name        = "lake"
    grants = [{
      sid           = "AllowCodeBuildDecrypt"
      principal_aws = "arn:aws:iam::883385860947:role/ck-cd-codebuild-apply"
      actions       = ["kms:GenerateDataKey*", "kms:Decrypt"]
    }]
  }

  assert {
    condition     = strcontains(aws_kms_key.this.policy, "\"AWS\":\"arn:aws:iam::883385860947:role/ck-cd-codebuild-apply\"") && strcontains(aws_kms_key.this.policy, "kms:GenerateDataKey*")
    error_message = "an AWS-principal grant must render the role ARN as an AWS principal with its actions"
  }
}

run "deletion_window_below_min_rejected" {
  command = plan

  variables {
    name                    = "x"
    deletion_window_in_days = 6
  }

  expect_failures = [var.deletion_window_in_days]
}

run "deletion_window_above_max_rejected" {
  command = plan

  variables {
    name                    = "x"
    deletion_window_in_days = 31
  }

  expect_failures = [var.deletion_window_in_days]
}
