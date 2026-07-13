variable "name" {
  description = "The `name` slot. Defaults to \"notifications\"; override per topic. Names the SNS topic, the Chatbot config, and the Chatbot role (<rendered-id>-chatbot)."
  type        = string
  default     = "notifications"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only (no leading/trailing hyphen)."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN encrypting the SNS topic (aws_sns_topic.kms_master_key_id). The key's policy must let the publishers' services (and chatbot.amazonaws.com to Decrypt) use it — grant that on the key, e.g. via the kms module's grants seam. null leaves the topic UNENCRYPTED and requires allow_unencrypted = true — for a stack where an encrypted-SNS→Chatbot grant chain (incl. the Chatbot service-linked role) isn't yet in place and would silently drop delivery."
  type        = string
  default     = null
}

variable "allow_unencrypted" {
  description = "Explicit opt-out acknowledging an UNENCRYPTED topic (kms_key_arn = null). Default false — a CMK is the baseline; you cannot get an unencrypted topic by omission, only by deliberately setting this. Exists only for a stack where a KMS grant to the Chatbot service-linked role isn't in place and encryption would drop Slack delivery."
  type        = bool
  default     = false
}

variable "slack_workspace_id" {
  description = "Slack workspace (team) ID for AWS Chatbot delivery — an input, not a baked identifier. The workspace must be authorized once in this account's Chatbot console before messages deliver."
  type        = string

  validation {
    condition     = can(regex("^T[A-Z0-9]+$", var.slack_workspace_id))
    error_message = "slack_workspace_id must be a Slack team ID (uppercase, starts with 'T'), not a workspace name or URL."
  }
}

variable "slack_channel_id" {
  description = "Slack channel ID for AWS Chatbot delivery — an input, not a '#channel' name."
  type        = string

  validation {
    condition     = can(regex("^C[A-Z0-9]+$", var.slack_channel_id))
    error_message = "slack_channel_id must be a Slack channel ID (uppercase, starts with 'C'), not the '#channel' name."
  }
}

variable "publishers" {
  description = <<-EOT
    Principals allowed sns:Publish to the topic, merged into the topic policy alongside the always-on
    root-account administration statement. Each becomes one Allow statement. Name EXACTLY ONE
    principal per entry: a service (principal_service, e.g. "cloudwatch.amazonaws.com",
    "events.amazonaws.com", "codestar-notifications.amazonaws.com") OR an AWS principal
    (principal_aws, a role/account ARN). SERVICE publishers automatically get an aws:SourceAccount =
    (this account) confused-deputy condition; add more conditions if needed.
  EOT
  type = list(object({
    sid               = string
    principal_service = optional(string)
    principal_aws     = optional(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []

  validation {
    condition     = length(var.publishers) == length(distinct([for p in var.publishers : p.sid]))
    error_message = "each publisher needs a unique sid."
  }

  validation {
    condition     = alltrue([for p in var.publishers : (p.principal_service != null) != (p.principal_aws != null)])
    error_message = "each publisher must set exactly one of principal_service or principal_aws."
  }

  validation {
    condition     = !contains([for p in var.publishers : p.sid], "AllowAccountRootAdministration")
    error_message = "the sid \"AllowAccountRootAdministration\" is reserved for the module's root-admin statement."
  }
}

variable "chatbot_guardrail_policy_arns" {
  description = "IAM guardrail policies bounding what Slack-issued AWS actions Chatbot may take. null (default) applies AWS-managed ReadOnlyAccess — a read-only channel that can never mutate resources."
  type        = list(string)
  default     = null
}

variable "logging_level" {
  description = "AWS Chatbot CloudWatch logging level (ERROR | INFO | NONE). Default ERROR."
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["ERROR", "INFO", "NONE"], var.logging_level)
    error_message = "logging_level must be ERROR, INFO, or NONE."
  }
}
