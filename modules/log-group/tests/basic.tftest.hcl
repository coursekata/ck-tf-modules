# Offline plan tests for the log-group primitive: the prefix + context-rendered name (proving the
# byte-identical datalake renders), retention, the AWS-managed-vs-CMK encryption switch, and the
# input guards. The context provider is real (pure computation); only aws is mocked.

mock_provider "aws" {}

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

# An ECS group with the /aws/ecs/ prefix and no attributes — must render byte-identically to
# ck-datalake's current dbt-fargate-runner log group (/aws/ecs/ck-datalake-stg-dbt-runner).
run "ecs_group_renders_with_prefix" {
  command = plan

  variables {
    name              = "dbt-runner"
    name_prefix       = "/aws/ecs/"
    environment       = "stg"
    retention_in_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/ecs/ck-datalake-stg-dbt-runner"
    error_message = "ECS log-group name must render /aws/ecs/ + the context id (surface empty drops out)"
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "retention must pass through"
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "kms_key_id must be null (AWS-managed) when kms_key_arn is unset"
  }
}

# A Lambda group WITH an attributes slot — must render byte-identically to ck-datalake's current
# snapshot-export-trigger log group (/aws/lambda/ck-datalake-stg-app-snapshot-export-trigger).
run "lambda_group_renders_with_attributes" {
  command = plan

  variables {
    name              = "app"
    attributes        = "snapshot-export-trigger"
    name_prefix       = "/aws/lambda/"
    environment       = "stg"
    retention_in_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/ck-datalake-stg-app-snapshot-export-trigger"
    error_message = "Lambda log-group name must render /aws/lambda/ + the context id including the attributes slot"
  }
}

# No prefix -> the bare rendered id.
run "no_prefix_renders_bare_id" {
  command = plan

  variables {
    name              = "cloudtrail"
    environment       = ""
    retention_in_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "ck-datalake-cloudtrail"
    error_message = "with no prefix and no environment the name is the bare rendered id"
  }
}

# A passed CMK threads through to kms_key_id.
run "cmk_threads_through" {
  command = plan

  variables {
    name              = "secure"
    retention_in_days = 365
    kms_key_arn       = "arn:aws:kms:us-west-2:232672477651:key/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:232672477651:key/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    error_message = "kms_key_arn must set kms_key_id on the group"
  }
}

# ── input guards ──────────────────────────────────────────────────────

run "rejects_unsupported_retention" {
  command = plan
  variables {
    name              = "x"
    retention_in_days = 45
  }
  expect_failures = [var.retention_in_days]
}

run "rejects_uppercase_name" {
  command = plan
  variables {
    name              = "BadName"
    retention_in_days = 30
  }
  expect_failures = [var.name]
}

run "rejects_bad_name_prefix" {
  command = plan
  variables {
    name              = "x"
    name_prefix       = "/aws/ecs/ bad space"
    retention_in_days = 30
  }
  expect_failures = [var.name_prefix]
}
