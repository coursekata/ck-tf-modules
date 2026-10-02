variable "name" {
  description = "Context name slot for the publishing role."
  type        = string
  default     = "image"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only."
  }
}

variable "attributes" {
  description = "Context attributes slot for the publishing role."
  type        = string
  default     = "publish"

  validation {
    condition     = var.attributes == "" || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.attributes))
    error_message = "attributes must be empty or lowercase alphanumerics with internal hyphens only."
  }
}

variable "policy_suffix" {
  description = "Suffix appended to the role name for its inline policy."
  type        = string
  default     = "ecr"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.policy_suffix))
    error_message = "policy_suffix must be lowercase alphanumerics with internal hyphens only."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account-level GitHub Actions OIDC provider."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must identify the GitHub Actions OIDC provider in an AWS account."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to publish images, in owner/repository form."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/repository form."
  }
}

variable "publish_ref" {
  description = "Full protected branch ref allowed to publish images."
  type        = string
  default     = "refs/heads/main"

  validation {
    condition     = can(regex("^refs/heads/[A-Za-z0-9._/-]+$", var.publish_ref))
    error_message = "publish_ref must be a full branch ref such as refs/heads/main."
  }
}

variable "repository_arn" {
  description = "ARN of the ECR repository the protected branch may publish to."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:ecr:[^:]+:[0-9]{12}:repository/.+$", var.repository_arn))
    error_message = "repository_arn must be an ECR repository ARN."
  }
}

variable "boundary_checks_enabled" {
  description = "Run live IAM simulations proving the role can authenticate and publish to the repository. Disable only for mocked tests before the role exists."
  type        = bool
  default     = true
}
