variable "name" {
  description = "Context name slot used for both CI roles. Use image for a shared lane or a component name such as frontend."
  type        = string
  default     = "image"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only."
  }
}

variable "stage_name" {
  description = "Optional context name slot for the pull-request role. Null uses name."
  type        = string
  default     = null

  validation {
    condition     = var.stage_name == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.stage_name))
    error_message = "stage_name must be null or lowercase alphanumerics with internal hyphens only."
  }
}

variable "publish_name" {
  description = "Optional context name slot for the promotion role. Null uses name."
  type        = string
  default     = null

  validation {
    condition     = var.publish_name == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.publish_name))
    error_message = "publish_name must be null or lowercase alphanumerics with internal hyphens only."
  }
}

variable "stage_attributes" {
  description = "Context attributes slot for the pull-request role."
  type        = string
  default     = "stage"

  validation {
    condition     = var.stage_attributes == "" || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.stage_attributes))
    error_message = "stage_attributes must be empty or lowercase alphanumerics with internal hyphens only."
  }
}

variable "publish_attributes" {
  description = "Context attributes slot for the branch-only promotion role."
  type        = string
  default     = "publish"

  validation {
    condition     = var.publish_attributes == "" || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.publish_attributes))
    error_message = "publish_attributes must be empty or lowercase alphanumerics with internal hyphens only."
  }
}

variable "stage_policy_suffix" {
  description = "Suffix appended to the staging role name for its inline policy."
  type        = string
  default     = "ecr"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.stage_policy_suffix))
    error_message = "stage_policy_suffix must be lowercase alphanumerics with internal hyphens only."
  }
}

variable "publish_policy_suffix" {
  description = "Suffix appended to the promotion role name for its inline policy."
  type        = string
  default     = "ecr"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.publish_policy_suffix))
    error_message = "publish_policy_suffix must be lowercase alphanumerics with internal hyphens only."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account-level GitHub Actions OIDC provider trusted by both roles."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must identify the GitHub Actions OIDC provider in an AWS account."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to stage and promote images, in owner/repository form."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/repository form."
  }
}

variable "publish_ref" {
  description = "Full Git ref allowed to assume the promotion role."
  type        = string
  default     = "refs/heads/main"

  validation {
    condition     = can(regex("^refs/heads/[A-Za-z0-9._/-]+$", var.publish_ref))
    error_message = "publish_ref must be a full branch ref such as refs/heads/main."
  }
}

variable "candidate_repository_arn" {
  description = "ARN of the candidate repository that pull requests may write and promotion may only read."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:ecr:[^:]+:[0-9]{12}:repository/.+$", var.candidate_repository_arn))
    error_message = "candidate_repository_arn must be an ECR repository ARN."
  }
}

variable "release_repository_arn" {
  description = "ARN of the release repository that promotion may write and pull requests may only inspect."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:ecr:[^:]+:[0-9]{12}:repository/.+$", var.release_repository_arn))
    error_message = "release_repository_arn must be an ECR repository ARN."
  }
}

variable "boundary_checks_enabled" {
  description = "Run live IAM simulations proving each role can write only its intended repository. Disable only for mocked tests before the roles exist."
  type        = bool
  default     = true
}
