# The module emits constants, so the suite pins those constants: a change to the org labeling
# policy must be deliberate (edit here) and is caught everywhere it's consumed via the ref bump.

run "emits_the_org_context_schema" {
  command = plan

  assert {
    condition     = output.tags_value_case == "lower"
    error_message = "tag values must be lowercased org-wide"
  }
  assert {
    condition     = output.properties["namespace"].required == true && output.properties["namespace"].min_length == 1
    error_message = "namespace must be the required, non-empty slot"
  }
  assert {
    condition     = output.properties["tenant"].required == false && output.properties["attributes"].required == false
    error_message = "only namespace is required; the rest are optional"
  }
  assert {
    condition     = contains(output.property_order, "stage") && contains(output.property_order, "attributes")
    error_message = "property_order must declare the full union (both stage and attributes) so every root's block is identical"
  }
}
