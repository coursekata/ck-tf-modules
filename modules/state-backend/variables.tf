# Namespace/domain and tags come from the cloudposse/context PROVIDER (configured by the consuming
# root). `name` defaults to "tfstate" — the bucket is always ck-<domain>-tfstate.

variable "name" {
  description = "The `name` slot. Defaults to \"tfstate\" (the bucket is always ck-<domain>-tfstate); override only to adopt a differently-named state bucket."
  type        = string
  default     = "tfstate"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only (no leading/trailing hyphen)."
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
