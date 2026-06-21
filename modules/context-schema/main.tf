# context-schema: the org's single source of truth for cloudposse/context provider
# configuration. An OUTPUTS-ONLY module (no resources, no providers) — each consuming root
# wires its `provider "context"` from these outputs and supplies only its repo-specific
# `values` (namespace/domain[/environment/surface]). The labeling policy then lives in ONE
# versioned place instead of being hand-copied into every root across ck-foundation,
# ck-tooling, and ck-datalake.
#
# Canonical spec: docs/labeling-standard.md (this module is its executable form).

locals {
  # The full property vocabulary every CK repo shares, in the org-wide canonical order:
  #   ck-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]
  # A root declares this whole union even when it only renders a subset — each `context_label`
  # data source picks its own slots, so widening the schema is INERT (it never changes a rendered
  # id) while keeping every provider block identical. `property_order` is only the default order
  # for a label that omits `properties`.
  context_property_order = ["namespace", "domain", "environment", "surface", "name", "attributes"]

  # Every property carries the SAME object shape (required / min_length / validation_regex all
  # set, never omitted) so the output is a cleanly-typed map(object(...)). That uniformity is
  # what lets the value flow through a module output into a provider block without type-coercion
  # surprises. Values are lowercase-only; namespace is the single mandatory, non-empty slot.
  # environment + surface are both optional and empty for single-env/single-surface repos
  # (foundation/tooling), so they render away — but ck-datalake's tier resources populate them
  # (environment = source-env-class, surface = data tier) to render the full id.
  context_properties = {
    namespace   = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    domain      = { required = false, min_length = 0, validation_regex = "^[a-z0-9-]*$" }
    environment = { required = false, min_length = 0, validation_regex = "^[a-z0-9-]*$" }
    surface     = { required = false, min_length = 0, validation_regex = "^[a-z0-9-]*$" }
    name        = { required = false, min_length = 0, validation_regex = "^[a-z0-9-]*$" }
    attributes  = { required = false, min_length = 0, validation_regex = "^[a-z0-9-]*$" }
  }

  # Tag VALUES are lowercased org-wide; tag KEYS stay Title-case (the provider default).
  context_tags_value_case = "lower"
}
