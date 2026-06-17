output "property_order" {
  description = "Default render order for the context provider. Wire into provider \"context\" { property_order = ... }."
  value       = local.context_property_order
}

output "properties" {
  description = "The shared property schema (vocabulary + per-slot validation). Wire into provider \"context\" { properties = ... }."
  value       = local.context_properties
}

output "tags_value_case" {
  description = "Org tag-value case policy (lower). Wire into provider \"context\" { tags_value_case = ... }."
  value       = local.context_tags_value_case
}
