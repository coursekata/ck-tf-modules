# Offline plan tests for the notifications primitive: the topic + Chatbot config render from context,
# the topic policy carries the root-admin statement, a SERVICE publisher gets the automatic
# aws:SourceAccount confused-deputy guard, the read-only guardrail defaults in, and the Slack-id +
# reserved-sid guards fire. Real aws provider OFFLINE (renders aws_iam_policy_document);
# aws_caller_identity stubbed via override_data.

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

variables {
  kms_key_arn        = "arn:aws:kms:us-west-2:883385860947:key/11111111-1111-1111-1111-111111111111"
  slack_workspace_id = "T082693J1N0"
  slack_channel_id   = "C0B807UHKTN"
}

run "topic_and_chatbot_render" {
  command = plan

  variables {
    environment = "prd"
    surface     = "datalake"
    name        = "lake-notify"
    publishers = [{
      sid               = "AllowEventBridgePublish"
      principal_service = "events.amazonaws.com"
    }]
  }

  assert {
    condition     = aws_sns_topic.this.name == "ck-cd-prd-datalake-lake-notify"
    error_message = "topic name must render the context id"
  }
  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == "arn:aws:kms:us-west-2:883385860947:key/11111111-1111-1111-1111-111111111111"
    error_message = "topic must be encrypted with the supplied CMK"
  }
  assert {
    condition     = strcontains(aws_sns_topic_policy.this.policy, "AllowAccountRootAdministration") && strcontains(aws_sns_topic_policy.this.policy, "arn:aws:iam::883385860947:root")
    error_message = "topic policy must carry the root-account administration statement"
  }
  # A service publisher must get the automatic SourceAccount confused-deputy guard — pinned by sid on
  # the parsed statement (not a loose substring), so the guard and the principal are co-located.
  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.topic.statement : length([for c in s.condition : c if c.variable == "aws:SourceAccount" && contains(c.values, "883385860947")]) == 1 if s.sid == "AllowEventBridgePublish"])
    error_message = "a service publisher must render with exactly one aws:SourceAccount = (this account) condition"
  }
  # The topic policy is scoped to the topic's OWN built ARN (plan-known), not an unknown resource attr.
  assert {
    condition     = strcontains(aws_sns_topic_policy.this.policy, "arn:aws:sns:us-west-2:883385860947:ck-cd-prd-datalake-lake-notify")
    error_message = "topic-policy statements must be scoped to the topic's own built ARN"
  }
  assert {
    condition     = aws_chatbot_slack_channel_configuration.this.slack_team_id == "T082693J1N0" && aws_chatbot_slack_channel_configuration.this.slack_channel_id == "C0B807UHKTN"
    error_message = "the Slack channel config must carry the workspace + channel ids"
  }
  assert {
    condition     = contains(aws_chatbot_slack_channel_configuration.this.guardrail_policy_arns, "arn:aws:iam::aws:policy/ReadOnlyAccess")
    error_message = "the Chatbot channel must default to the ReadOnlyAccess guardrail"
  }
}

run "bad_slack_channel_is_rejected" {
  command = plan

  variables {
    name             = "x"
    slack_channel_id = "#general"
  }

  expect_failures = [var.slack_channel_id]
}

run "reserved_publisher_sid_is_rejected" {
  command = plan

  variables {
    name = "x"
    publishers = [{
      sid               = "AllowAccountRootAdministration"
      principal_service = "events.amazonaws.com"
    }]
  }

  expect_failures = [var.publishers]
}

# The AWS-principal branch: a role ARN must render under an "AWS" principal AND must NOT receive the
# auto aws:SourceAccount condition (that guard is service-only). This is the negative half of the
# confused-deputy invariant — the service-only run above proves the positive half.
run "aws_principal_publisher_has_no_source_account" {
  command = plan

  variables {
    environment = "prd"
    surface     = "datalake"
    name        = "lake-notify"
    publishers = [{
      sid           = "AllowCodeBuildPublish"
      principal_aws = "arn:aws:iam::883385860947:role/ck-cd-codebuild-apply"
    }]
  }

  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.topic.statement : anytrue([for p in s.principals : p.type == "AWS"]) if s.sid == "AllowCodeBuildPublish"])
    error_message = "an AWS-principal publisher must render with principal type AWS"
  }
  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.topic.statement : length([for c in s.condition : c if c.variable == "aws:SourceAccount"]) == 0 if s.sid == "AllowCodeBuildPublish"])
    error_message = "an AWS-principal publisher must NOT get the auto aws:SourceAccount condition (service-only)"
  }
}

run "guardrail_override_replaces_default" {
  command = plan

  variables {
    name                          = "x"
    chatbot_guardrail_policy_arns = ["arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"]
  }

  assert {
    condition     = contains(aws_chatbot_slack_channel_configuration.this.guardrail_policy_arns, "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess") && !contains(aws_chatbot_slack_channel_configuration.this.guardrail_policy_arns, "arn:aws:iam::aws:policy/ReadOnlyAccess")
    error_message = "an explicit guardrail override must replace the ReadOnlyAccess default"
  }
}

run "bad_slack_workspace_is_rejected" {
  command = plan

  variables {
    name               = "x"
    slack_workspace_id = "coursekata"
  }

  expect_failures = [var.slack_workspace_id]
}

# An unencrypted topic is representable ONLY with the explicit opt-out (foundation's deferred-CMK case).
run "unencrypted_topic_when_opted_in" {
  command = plan

  variables {
    name              = "x"
    kms_key_arn       = null
    allow_unencrypted = true
  }

  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == null
    error_message = "kms_key_arn = null with allow_unencrypted must leave the topic unencrypted (no kms_master_key_id)"
  }
}

# ...and you cannot get there by omission — null CMK without the opt-out is rejected (secure-by-default).
run "null_kms_without_optin_is_rejected" {
  command = plan

  variables {
    name        = "x"
    kms_key_arn = null
  }

  expect_failures = [aws_sns_topic.this]
}
