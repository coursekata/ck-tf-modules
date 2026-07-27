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
  description = "ARN of the hub CI APPLY role (in the tooling account) permitted to sts:AssumeRole the apply (RW) deploy role — the GHA gated write path (the hub apply role is itself assumable only from the spoke's protected GitHub Environment). Optional (default null): a spoke on a non-GHA executor sets apply_principal_arns instead and leaves this null. At least one apply principal (this or apply_principal_arns) is required."
  type        = string
  default     = null

  validation {
    condition     = var.hub_apply_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/[^*]+$", coalesce(var.hub_apply_role_arn, "x")))
    error_message = "hub_apply_role_arn must be null or a concrete IAM role ARN (arn:aws:iam::<account>:role/<name>) with no wildcard."
  }
}

variable "apply_principal_arns" {
  description = "Additional concrete IAM principal ARNs trusted to sts:AssumeRole the apply (RW) deploy role, beyond hub_apply_role_arn. Use for a non-GHA executor — e.g. the CodeBuild apply role in the CodePipeline delivery model. A CodePipeline spoke sets this and leaves hub_apply_role_arn null to retire the GHA apply path. At least one apply principal (this or hub_apply_role_arn) is required."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.apply_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/[^*]+$", arn))])
    error_message = "each apply_principal_arns entry must be a concrete IAM role ARN (arn:aws:iam::<account>:role/<name>) with no wildcard."
  }
}

variable "hub_plan_role_arn" {
  description = "ARN of the hub CI PLAN role permitted to sts:AssumeRole the plan (RO) deploy role — the GHA PR-preview read path. Optional (default null): a spoke that only plans on a non-GHA executor sets plan_principal_arns instead. The plan role is created when either this or plan_principal_arns is set; omit both for an apply-only spoke."
  type        = string
  default     = null

  validation {
    condition     = var.hub_plan_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/[^*]+$", coalesce(var.hub_plan_role_arn, "x")))
    error_message = "hub_plan_role_arn must be null or a concrete IAM role ARN with no wildcard."
  }
}

variable "plan_principal_arns" {
  description = "Additional concrete IAM principal ARNs trusted to sts:AssumeRole the plan (RO) deploy role, beyond hub_plan_role_arn. Use for a non-GHA executor — e.g. the CodeBuild plan and drift roles in the CodePipeline delivery model, whose in-pipeline Plan and Drift builds assume the plan role to produce/refresh the reviewed plan. A CodePipeline spoke sets this alongside hub_plan_role_arn (GHA still previews PRs) — the mirror of apply_principal_arns."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.plan_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/[^*]+$", arn))])
    error_message = "each plan_principal_arns entry must be a concrete IAM role ARN (arn:aws:iam::<account>:role/<name>) with no wildcard."
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
  description = "Managed IAM policy ARNs attached to the plan (RO) deploy role. Only used when the plan role is created (hub_plan_role_arn and/or plan_principal_arns set)."
  type        = list(string)
  default     = []
}

variable "managed_role_boundary" {
  description = <<-EOT
    Opt-in privilege-escalation guard for a spoke whose apply role MINTS IAM roles. Set it and the
    module creates a permissions-boundary policy from `policy_document` and generates the entire
    role-management grant itself, so the spoke never hand-writes one: every widening action
    (CreateRole/PutRolePolicy/AttachRolePolicy/...) is conditioned on the minted role carrying THAT
    boundary, the boundary can never be detached, the boundary policy can never be rewritten, and
    the deploy roles are explicitly denied to themselves. `role_arn_patterns` are the roles the
    apply role may manage — they MUST NOT match the deploy roles' own ARNs (the module denies that
    regardless, but a pattern that overlaps them is a design smell). Leave null for a spoke whose
    apply role mints no roles.
  EOT

  type = object({
    policy_document   = string
    role_arn_patterns = list(string)
  })
  default = null

  validation {
    condition     = var.managed_role_boundary == null || length(try(var.managed_role_boundary.role_arn_patterns, [])) > 0
    error_message = "managed_role_boundary.role_arn_patterns must list at least one role ARN pattern (an empty set grants nothing and silently disables the guard)."
  }

  validation {
    condition = var.managed_role_boundary == null || alltrue([
      for arn in var.managed_role_boundary.role_arn_patterns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", arn))
    ])
    error_message = "each managed_role_boundary.role_arn_patterns entry must be an IAM role ARN (arn:aws:iam::<account>:role/<pattern>); a bare wildcard or a non-role ARN would let the apply role manage principals outside the intended set."
  }

  validation {
    condition = var.managed_role_boundary == null || length(distinct([
      for arn in var.managed_role_boundary.role_arn_patterns : regex("^arn:aws:iam::([0-9]{12}):role/", arn)[0]
    ])) == 1
    error_message = "all managed_role_boundary.role_arn_patterns must name the SAME account — the boundary policy is created in that one account, and a pattern pointing elsewhere would be silently unbounded."
  }
}

variable "plan_inline_policy" {
  description = "Optional inline IAM policy JSON for the plan (RO) deploy role. Only used when the plan role is created (hub_plan_role_arn and/or plan_principal_arns set)."
  type        = string
  default     = null
}
