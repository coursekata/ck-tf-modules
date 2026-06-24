# Fixture for context-schema's provider-compatibility suite. It configures a real context provider
# from the schema's emitted outputs and renders a label — so the suite can prove those constants are
# accepted as valid provider configuration, not merely well-formed data. context-schema itself stays
# outputs-only (no provider, no resources); this stands in for a consuming root.

terraform {
  required_version = ">= 1.11.6, < 2.0"
  required_providers {
    context = {
      source  = "cloudposse/context"
      version = "~> 0.5.0"
    }
  }
}

variable "property_order" {
  description = "context-schema's property_order output, wired into the provider."
  type        = list(string)
}

variable "properties" {
  description = "context-schema's properties (schema + per-slot validation) output."
  type = map(object({
    required         = bool
    min_length       = number
    validation_regex = string
  }))
}

variable "tags_value_case" {
  description = "context-schema's tags_value_case output."
  type        = string
}

variable "values" {
  description = "Base context values a consuming root supplies (namespace/domain/...)."
  type        = map(string)
}

provider "context" {
  property_order  = var.property_order
  properties      = var.properties
  tags_value_case = var.tags_value_case
  values          = var.values
}

data "context_label" "this" {
  values = { name = "tfstate" }
}

data "context_tags" "this" {
  values = { name = "tfstate" }
}

output "rendered" {
  description = "The rendered label id."
  value       = data.context_label.this.rendered
}

output "tags" {
  description = "The rendered tag set."
  value       = data.context_tags.this.tags
}
