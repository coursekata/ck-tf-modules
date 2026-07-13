variable "name" {
  description = "The `name` slot. Defaults to \"kms\"; override per key (the key alias is alias/<rendered-id>)."
  type        = string
  default     = "kms"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only (no leading/trailing hyphen)."
  }
}

variable "description" {
  description = "Optional key description. \"\" (default) renders \"CMK for <rendered-id>.\"."
  type        = string
  default     = ""
}

variable "deletion_window_in_days" {
  description = "Days before a scheduled key deletion completes (7-30). Default 30 — the maximum recovery window."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "enable_key_rotation" {
  description = "Enable annual automatic key rotation. Default true (the org baseline)."
  type        = bool
  default     = true
}

variable "grants" {
  description = <<-EOT
    Allow grants merged into the key policy alongside the always-on root-account administration
    statement. Each grant becomes one Allow statement whose resource is the key itself ("*" in a
    key policy). Name EXACTLY ONE principal per grant: a service (principal_service, e.g.
    "cloudwatch.amazonaws.com" or "chatbot.amazonaws.com") OR an AWS principal (principal_aws, a
    role/account ARN — e.g. a CodeBuild or CodePipeline service role that must GenerateDataKey /
    Decrypt to read an SSE-KMS artifact). Add an aws:SourceAccount condition on service grants for
    confused-deputy defense.
  EOT
  type = list(object({
    sid               = string
    principal_service = optional(string) # a Service principal, e.g. "events.amazonaws.com"
    principal_aws     = optional(string) # OR an AWS principal ARN, e.g. an IAM role
    actions           = list(string)     # e.g. ["kms:GenerateDataKey*", "kms:Decrypt"]
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []

  validation {
    condition     = length(var.grants) == length(distinct([for g in var.grants : g.sid]))
    error_message = "each grant needs a unique sid."
  }

  # Exactly one principal per grant — a Service XOR an AWS principal. Both-or-neither is ambiguous.
  validation {
    condition     = alltrue([for g in var.grants : (g.principal_service != null) != (g.principal_aws != null)])
    error_message = "each grant must set exactly one of principal_service or principal_aws."
  }

  # "EnableRootAccountKeyAdministration" is reserved for the always-on root statement.
  validation {
    condition     = !contains([for g in var.grants : g.sid], "EnableRootAccountKeyAdministration")
    error_message = "the sid \"EnableRootAccountKeyAdministration\" is reserved for the module's root-admin statement."
  }
}
