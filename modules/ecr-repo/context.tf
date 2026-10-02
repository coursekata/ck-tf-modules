# context.tf — BYTE-IDENTICAL across every label-rendering module. Renders the org label + tags from
# the context provider and asserts the result is a valid org id. Do not edit per-module. Each module
# declares its own `name` (with its opinionated default); a slot left null inherits the provider's
# base value, "" suppresses it, a value overrides.

variable "environment" {
  description = "Optional `environment` slot. null/unset inherits the provider base; \"\" suppresses it here; a value overrides."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits, and hyphens only (or \"\")."
  }
}

variable "surface" {
  description = "Optional `surface` slot. null/unset inherits the provider base; \"\" suppresses it here; a value overrides."
  type        = string
  default     = null

  validation {
    condition     = var.surface == null || can(regex("^[a-z0-9-]*$", var.surface))
    error_message = "surface must be lowercase letters, digits, and hyphens only (or \"\")."
  }
}

variable "attributes" {
  description = "Optional `attributes` slot. null/unset inherits the provider base; \"\" suppresses it here; a value overrides."
  type        = string
  default     = null

  validation {
    condition     = var.attributes == null || can(regex("^[a-z0-9-]*$", var.attributes))
    error_message = "attributes must be lowercase letters, digits, and hyphens only (or \"\")."
  }
}

locals {
  # No property list — the provider owns the slot order. var.name is declared per-module.
  label_values = { for k, v in {
    name        = var.name
    environment = var.environment
    surface     = var.surface
    attributes  = var.attributes
  } : k => v if v != null }
}

data "context_label" "this" {
  values = local.label_values
}

data "context_tags" "this" {
  values = local.label_values

  # The org contract: the rendered id must be lowercase, hyphen-delimited, with no empty/edge segments.
  # Hosted here (not on context_label) because a data source's precondition can't reference itself.
  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", data.context_label.this.rendered))
      error_message = "rendered label must be a valid org id (lowercase, hyphen-delimited, no empty segments)."
    }
  }
}
