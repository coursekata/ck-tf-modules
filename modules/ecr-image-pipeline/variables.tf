variable "images" {
  description = "The images this GitHub repository builds, by component name, such as dbt-runner. Each gets a candidate, a release and a cache repository."
  type        = set(string)

  validation {
    condition     = length(var.images) > 0 && alltrue([for i in var.images : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", i))])
    error_message = "images must name at least one component, each lowercase alphanumerics with internal hyphens only."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must identify the GitHub Actions OIDC provider in an AWS account."
  }
}

variable "github_repository" {
  description = "The GitHub repository whose workflows may assume the three roles, as GitHub writes it in the OIDC subject: owner/repository for a repository created before 2026-07-15 and not renamed or transferred since, otherwise owner@<owner id>/repository@<repository id>."
  type        = string

  validation {
    condition = (
      can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository)) ||
      can(regex("^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.github_repository))
    )
    error_message = "github_repository must be owner/repository, or owner@<owner id>/repository@<repository id> for GitHub's immutable subject form."
  }
}

variable "default_branch" {
  description = "The repository's default branch. Only a push to it may assume the candidate role."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.default_branch)) && !startswith(var.default_branch, "refs/")
    error_message = "default_branch must be a branch name such as main, without refs/heads/."
  }
}

variable "release_readers" {
  description = "Repositories whose Renovate reads the release repositories to move an image pin, each mapped to its own default branch. A repository is written as GitHub writes it in the OIDC subject, in either form github_repository accepts, and the branch is a name such as main. Each gets a release-read role trusted on that branch, which may describe and pull the release repositories and nothing else. The role's name drops the ids of the immutable form and renders the rest in lowercase with hyphens, so a repository keeps its role when it moves to that form. A repository that is its own consumer names itself."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for r in keys(var.release_readers) :
      can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", r)) || can(regex("^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", r))
    ])
    error_message = "each release reader must be owner/repository, or owner@<owner id>/repository@<repository id> for GitHub's immutable subject form."
  }

  validation {
    condition     = alltrue([for b in values(var.release_readers) : can(regex("^[A-Za-z0-9._/-]+$", b)) && !startswith(b, "refs/")])
    error_message = "each release reader's branch must be a branch name such as main, without refs/heads/."
  }
}

variable "image_qualifier_in_names" {
  description = "Whether each repository's name carries image- before its area, as ck-datalake-prd-dbt-runner-image-release does. The lake keeps that form, since an ECR repository cannot be renamed. A new producer sets false: its image's name and the area say enough, as in ck-app-stg-web-server-release."
  type        = bool
  default     = true
}

variable "sibling_release_repository_arns" {
  description = "Release repositories of another producer in this account whose images this producer's builds consume as a build context, as ck-app-web's web server consumes the api contract. The candidate and cache-read roles may describe and pull them, so a pull request's build and a default-branch build both can; no role may write them, and the release role and the readers get nothing."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.sibling_release_repository_arns : can(regex("^arn:[^:]+:ecr:[a-z0-9-]+:[0-9]{12}:repository/[a-z0-9._/-]+$", a))])
    error_message = "each sibling release repository must be an ECR repository ARN."
  }
}
