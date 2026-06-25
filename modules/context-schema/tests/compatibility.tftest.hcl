# Proves context-schema's emitted constants are not merely well-formed data but VALID context
# provider configuration. run "schema" computes the module's outputs; run "render" feeds them into a
# real provider (via the fixture) and asserts the canonical render. A malformed property_order or
# properties fails HERE, in context-schema, instead of silently in every consuming root.

run "schema" {
  command = apply
}

run "configures_a_valid_provider_and_renders_canonically" {
  command = apply

  module {
    source = "./tests/fixture"
  }

  variables {
    property_order  = run.schema.property_order
    properties      = run.schema.properties
    tags_value_case = run.schema.tags_value_case
    values          = { namespace = "ck", domain = "datalake" }
  }

  # The schema configures a provider that renders the canonical id, empty slots dropped.
  assert {
    condition     = output.rendered == "ck-datalake-tfstate"
    error_message = "schema must configure a context provider that renders ck-datalake-tfstate"
  }

  # And the same config drives the classification tags (proves properties + tags_value_case are live).
  assert {
    condition     = output.tags["Namespace"] == "ck" && output.tags["Domain"] == "datalake"
    error_message = "schema's properties/tags_value_case must produce the base classification tags"
  }
}
