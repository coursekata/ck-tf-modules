# The bucket name renders from the context provider in the org canonical order:
# <namespace>-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]. This module is instanced
# (one call per bucket), so `name` has no default — each caller names its bucket via the slots;
# the convention is enforced by construction.
variable "name" {
  description = "The context `name` slot for the bucket (e.g. \"cloudtrail\" -> ck-<domain>-cloudtrail)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name must be lowercase letters, digits, and hyphens only."
  }
}

variable "attributes" {
  description = "Optional context `attributes` slot, appended as a trailing qualifier (e.g. \"logs\" -> ...-cloudtrail-logs). \"\" renders no suffix."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.attributes))
    error_message = "attributes must be lowercase letters, digits, and hyphens only (or empty)."
  }
}

variable "versioning_enabled" {
  description = "Enable S3 versioning. Must be true when object_lock is set."
  type        = bool
  default     = true
}

variable "object_lock" {
  description = <<-EOT
    S3 Object Lock default retention, or null to create the bucket without Object Lock.
    Set exactly one of retention_years / retention_days. Requires versioning_enabled.
    GOVERNANCE allows privileged bypass (break-glass); COMPLIANCE allows none.
  EOT
  type = object({
    mode            = string
    retention_years = optional(number)
    retention_days  = optional(number)
  })
  default = null

  validation {
    condition     = var.object_lock == null || contains(["GOVERNANCE", "COMPLIANCE"], try(var.object_lock.mode, ""))
    error_message = "object_lock.mode must be GOVERNANCE or COMPLIANCE."
  }

  validation {
    condition = var.object_lock == null || (
      (try(var.object_lock.retention_years, null) != null) != (try(var.object_lock.retention_days, null) != null)
    )
    error_message = "object_lock requires exactly one of retention_years or retention_days."
  }

  # coalesce (not try) to skip nulls: an unset optional() attribute returns null, which is
  # a value, so try() would stop at it. coalesce skips nulls and lands on the set one.
  validation {
    condition     = var.object_lock == null || coalesce(try(var.object_lock.retention_years, null), try(var.object_lock.retention_days, null), 0) > 0
    error_message = "object_lock retention must be a positive number."
  }
}

variable "object_ownership" {
  description = <<-EOT
    S3 Object Ownership. Defaults to BucketOwnerEnforced (ACLs disabled — the recommended
    posture for a durable audit bucket). Set null to leave ownership unmanaged, e.g. when
    importing an existing bucket to no-diff that has no explicit ownership-controls config.
  EOT
  type        = string
  default     = "BucketOwnerEnforced"

  validation {
    condition     = var.object_ownership == null || contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter, or null."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS. null uses SSE-S3 (AES256), the default until a key-management driver exists."
  type        = string
  default     = null
}

variable "lifecycle_rule" {
  description = <<-EOT
    Optional lifecycle knobs on a single all-objects rule. Any null field omits that
    action; if the object itself is null (or every field is null) no lifecycle
    configuration is created (lets a bucket import to no-diff against one with none).
  EOT
  type = object({
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    abort_incomplete_multipart_days    = optional(number)
  })
  default = null
}

variable "tls_only" {
  description = "Attach a bucket-policy statement denying non-TLS (aws:SecureTransport=false) access."
  type        = bool
  default     = true
}

variable "grants" {
  description = <<-EOT
    Service-delivery grants merged into the bucket's single policy (alongside tls_only). Each
    grant becomes one Allow statement, and the bucket's OWN ARN is injected here — the resource
    is the bucket ARN plus each key_suffix ("" = the bucket itself, "/AWSLogs/<acct>/*" = an
    object path). A grant carries NO bucket reference, so a grant-producer module (e.g.
    cloudtrail-delivery-grant) composes without depending on this one.
  EOT
  type = list(object({
    sid               = string
    principal_service = string                       # e.g. "cloudtrail.amazonaws.com"
    actions           = list(string)                 # e.g. ["s3:PutObject"]
    key_suffixes      = optional(list(string), [""]) # appended to the bucket ARN; "" = bare bucket
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
}
