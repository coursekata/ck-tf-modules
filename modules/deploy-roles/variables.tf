variable "expected_account_id" {
  description = "AWS account these deploy roles must be created in (the spoke account). A precondition fails the plan if the provider resolved elsewhere, so a wrong-profile apply can't mint deploy roles in the wrong account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
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

variable "name" {
  description = "The context `name` slot for the roles. Renders as <namespace>-<tenant>-<name> (apply) and <namespace>-<tenant>-<name>-plan (plan), e.g. ck-org-deploy / ck-org-deploy-plan."
  type        = string
  default     = "deploy"
}
