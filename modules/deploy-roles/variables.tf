# Namespace/domain and tags come from the cloudposse/context PROVIDER (configured by the consuming
# root). `name` defaults to "deploy"; the apply/plan role names append the role type as a suffix.

variable "name" {
  description = "The `name` slot for the roles. Defaults to \"deploy\" (ck-<domain>-deploy-apply / -plan); override per spoke."
  type        = string
  default     = "deploy"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only (no leading/trailing hyphen)."
  }
}

variable "hub_apply_role_arn" {
  description = "ARN of the hub CI APPLY role (in the tooling account) permitted to sts:AssumeRole the apply (RW) deploy role. This is the gated write path: the hub apply role is itself assumable only from the spoke's protected GitHub Environment."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[^*]+$", var.hub_apply_role_arn))
    error_message = "hub_apply_role_arn must be a concrete IAM role ARN (arn:aws:iam::<account>:role/<name>) with no wildcard."
  }
}

variable "hub_plan_role_arn" {
  description = "ARN of the hub CI PLAN role permitted to sts:AssumeRole the plan (RO) deploy role. Leave null for an apply-only spoke (no PR plan role is created)."
  type        = string
  default     = null

  validation {
    condition     = var.hub_plan_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/[^*]+$", coalesce(var.hub_plan_role_arn, "x")))
    error_message = "hub_plan_role_arn must be null or a concrete IAM role ARN with no wildcard."
  }
}

variable "apply_policy_arns" {
  description = "Managed IAM policy ARNs attached to the apply (RW) deploy role — the spoke's deploy permissions. Use these or apply_inline_policy (at least one is required)."
  type        = list(string)
  default     = []
}

variable "apply_inline_policy" {
  description = "Optional inline IAM policy JSON for the apply (RW) deploy role (e.g. from a data.aws_iam_policy_document)."
  type        = string
  default     = null
}

variable "plan_policy_arns" {
  description = "Managed IAM policy ARNs attached to the plan (RO) deploy role. Only used when hub_plan_role_arn is set."
  type        = list(string)
  default     = []
}

variable "plan_inline_policy" {
  description = "Optional inline IAM policy JSON for the plan (RO) deploy role. Only used when hub_plan_role_arn is set."
  type        = string
  default     = null
}
