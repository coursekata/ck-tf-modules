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
  description = "KMS key ARN for SSE-KMS using an EXISTING key. null uses SSE-S3 (AES256). Mutually exclusive with create_kms (which makes the bucket its own key)."
  type        = string
  default     = null
}

variable "create_kms" {
  description = <<-EOT
    Create a dedicated CMK + alias (alias/<rendered-id>) for this bucket and encrypt with it
    (SSE-KMS, bucket-key on; annual rotation; 30-day deletion window). The key's POLICY is left
    to the caller (attach an aws_kms_key_policy referencing the kms_key_id/kms_key_arn outputs) so
    it can grant concrete principal ARNs. Use for a tier whose writer requires a customer key
    (e.g. the raw tier — RDS snapshot-export REQUIRES a CMK). Default false (SSE-S3 or
    kms_key_arn). Mutually exclusive with kms_key_arn.
  EOT
  type        = bool
  default     = false

  validation {
    condition     = !(var.create_kms && var.kms_key_arn != null)
    error_message = "set at most one of create_kms or kms_key_arn — a bucket has one encryption key source."
  }
}

variable "require_sse_kms" {
  description = <<-EOT
    When the bucket has a CMK (create_kms or kms_key_arn), add two Deny statements to the bucket
    policy that refuse any PutObject not encrypted with SSE-KMS pinned to THIS bucket's key
    (DenyNonKmsUploads + DenyWrongKmsKey, StringNotEqualsIfExists — a header-less upload is denied,
    not defaulted). Inert without a CMK. Default false (no upload-encryption invariant).
  EOT
  type        = bool
  default     = false

  validation {
    condition     = !var.require_sse_kms || var.create_kms || var.kms_key_arn != null
    error_message = "require_sse_kms needs a CMK — set create_kms or kms_key_arn."
  }
}

variable "environment" {
  description = "Optional call-time `environment` slot override (e.g. \"stg\"/\"prd\"). Renders ck-<domain>-<environment>-…; \"\" leaves the provider's value (empty for single-env repos). Lets one provider config name buckets across environments."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits, and hyphens only (or empty)."
  }
}

variable "surface" {
  description = "Optional call-time `surface` slot override (e.g. a datalake tier \"raw\"/\"staging\"/\"analytical\"). Renders …-<surface>-<name>; \"\" leaves the provider's value. Lets one provider config name buckets across surfaces/tiers."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.surface))
    error_message = "surface must be lowercase letters, digits, and hyphens only (or empty)."
  }
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
    expiration_prefix                  = optional(string, "") # "" = bucket-wide; set to scope expiry to a key prefix (e.g. "_athena-results/")
  })
  default = null

  # A prefix without an action does nothing (no lifecycle resource is created) — fail loudly
  # instead of silently dropping it.
  validation {
    condition = var.lifecycle_rule == null || try(var.lifecycle_rule.expiration_prefix, "") == "" || anytrue([
      try(var.lifecycle_rule.expiration_days, null) != null,
      try(var.lifecycle_rule.noncurrent_version_expiration_days, null) != null,
      try(var.lifecycle_rule.abort_incomplete_multipart_days, null) != null,
    ])
    error_message = "lifecycle_rule.expiration_prefix has no effect without a lifecycle action — set expiration_days (or another action)."
  }
}

variable "tls_only" {
  description = "Attach a bucket-policy statement denying non-TLS (aws:SecureTransport=false) access."
  type        = bool
  default     = true
}

variable "grants" {
  description = <<-EOT
    Allow grants merged into the bucket's single policy (alongside tls_only). Each grant becomes
    one Allow statement, and the bucket's OWN ARN is injected here — the resource is the bucket
    ARN plus each key_suffix ("" = the bucket itself, "/AWSLogs/<acct>/*" = an object path). A
    grant carries NO bucket reference, so a grant-producer module (e.g. cloudtrail-delivery-grant)
    composes without depending on this one. Each grant names EXACTLY ONE principal: a service
    (principal_service, e.g. "cloudtrail.amazonaws.com") OR an AWS principal (principal_aws, a
    role/account ARN — e.g. a data-export role that writes to a tier bucket).
  EOT
  type = list(object({
    sid               = string
    principal_service = optional(string)             # a Service principal, e.g. "cloudtrail.amazonaws.com"
    principal_aws     = optional(string)             # OR an AWS principal ARN, e.g. an IAM role
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

  # Exactly one principal per grant — a Service XOR an AWS principal. Both-or-neither is ambiguous.
  validation {
    condition     = alltrue([for g in var.grants : (g.principal_service != null) != (g.principal_aws != null)])
    error_message = "each grant must set exactly one of principal_service or principal_aws."
  }
}
