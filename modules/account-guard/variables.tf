variable "expected_account_id" {
  description = "AWS account this root must run against. The guard fails the plan if the provider resolved to a different account, so a wrong-profile/-role apply can never create resources in the wrong account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}
