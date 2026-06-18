# Namespace/tenant/stage and tags come from the cloudposse/context PROVIDER (configured by the
# consuming root), not from module inputs; `name` is pinned to "tfstate" in main.tf. Only the
# inputs below are specific to this module.

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent object versions before expiry. Versioning keeps state history; this bounds how long superseded versions accumulate."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days > 0
    error_message = "noncurrent_version_expiration_days must be greater than 0."
  }
}
