variable "name" {
  description = "The component being imaged, such as frontend or dbt-runner. The caller normally sets attributes to image, image-candidate, or image-staging."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only."
  }
}

variable "retain_n_images" {
  description = "Keep this many most-recent images, expiring the rest by count. Suits a repository holding only released images, where the count is a rollback depth. Mutually exclusive with expire_after_days; exactly one of the two is required."
  type        = number
  default     = null

  validation {
    condition     = var.retain_n_images == null || (var.retain_n_images >= 1 && floor(var.retain_n_images) == var.retain_n_images)
    error_message = "retain_n_images must be a whole number of at least 1, as ECR rejects a fractional count."
  }
}

variable "expire_after_days" {
  description = "Expire images this many days after they were pushed. Suits a repository of build candidates, where age is the better measure and a count would let a busy week evict something still in review. Mutually exclusive with retain_n_images; exactly one of the two is required."
  type        = number
  default     = null

  validation {
    condition     = var.expire_after_days == null || (var.expire_after_days >= 1 && floor(var.expire_after_days) == var.expire_after_days)
    error_message = "expire_after_days must be a whole number of at least 1, as ECR rejects a fractional count."
  }
}
