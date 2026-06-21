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
    condition     = output.properties["domain"].required == false && output.properties["attributes"].required == false
    error_message = "only namespace is required; the rest are optional"
  }
  # Pin the full canonical order. environment + surface are optional (empty for single-env repos,
  # so they render away) but must occupy their canonical positions so a multi-env repo (ck-datalake)
  # renders ck-<domain>-<environment>-<surface>-<name> and every root's provider block is identical.
  assert {
    condition = (
      output.property_order[0] == "namespace" &&
      output.property_order[1] == "domain" &&
      output.property_order[2] == "environment" &&
      output.property_order[3] == "surface" &&
      output.property_order[4] == "name" &&
      output.property_order[5] == "attributes"
    )
    error_message = "property_order must be the canonical [namespace, domain, environment, surface, name, attributes]"
  }
}
