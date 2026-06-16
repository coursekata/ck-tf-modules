# Namespace/tenant/stage and tags come from the cloudposse/context PROVIDER (configured by the
# consuming root), not from module inputs; `name` is pinned to "tfstate" in main.tf. Only the
# inputs below are specific to this module.

variable "expected_account_id" {
  description = "AWS account the bucket must be created in. A precondition fails the plan if the provider resolves to a different account, so a wrong-profile apply can't land the bucket elsewhere."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent object versions before expiry. Versioning keeps state history; this bounds how long superseded versions accumulate."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days > 0
    error_message = "noncurrent_version_expiration_days must be greater than 0."
  }
}
