# context-schema

The org's single source of truth for the **shape** of `cloudposse/context` provider
configuration. An **outputs-only** module (no resources, no providers): it emits the labeling
*schema* — `property_order`, the property `properties` definition + validation, and
`tags_value_case` — but **no values**. The schema then lives in ONE versioned place instead of
being hand-copied into every consuming root, which supplies only its repo-specific `values`
(`namespace`/`tenant`).

This module does **not** install or replace the `cloudposse/context` provider — you still
declare that provider in `required_providers` as usual. It only supplies the *configuration*
the provider block would otherwise hand-roll. So a root that wants org-standard naming does
three things: **declare** the provider, **pull** the schema from this module, and **configure**
the provider from it.

Canonical spec: the org [labeling standard](https://github.com/coursekata/ck-tf-modules/blob/main/docs/labeling-standard.md) — this module is its executable form.

## Usage

```hcl
# 1. Declare the cloudposse/context provider (this module configures it, it doesn't replace it).
terraform {
  required_providers {
    context = {
      source  = "cloudposse/context"
      version = "~> 0.5.0"
    }
  }
}

# 2. Pull the org labeling schema.
module "context_schema" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/context-schema?ref=v0.2.1"
}

# 3. Configure the provider from the module; supply only this repo's values.
provider "context" {
  property_order  = module.context_schema.property_order
  properties      = module.context_schema.properties
  tags_value_case = module.context_schema.tags_value_case

  values = {
    namespace = "ck"
    tenant    = "org" # this repo's discriminator
  }
}
```

Resources then read `data.context_label` (names) and `data.context_tags` (tags) as usual —
this changes only where the provider's *config* comes from, not how you consume it.

Every root declares the **full property union** (`namespace`, `tenant`, `stage`, `name`,
`attributes`) even if it renders only a subset — each `data.context_label` picks its own
slots, so a wider schema never changes a rendered id but keeps every provider block identical.

> **Adoption note:** configuring a provider from a module output is a supported but
> lightly-trodden path. The uniform property shape (every slot sets `required`/`min_length`/
> `validation_regex`) is deliberate — it makes the `properties` output a cleanly-typed
> `map(object(...))` that flows into the provider without type-coercion surprises. Verify
> `init`/`validate`/a label render on the first root before rolling it out repo-wide.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.6, < 2.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_properties"></a> [properties](#output\_properties) | The shared property schema (vocabulary + per-slot validation). Wire into provider "context" { properties = ... }. |
| <a name="output_property_order"></a> [property\_order](#output\_property\_order) | Default render order for the context provider. Wire into provider "context" { property\_order = ... }. |
| <a name="output_tags_value_case"></a> [tags\_value\_case](#output\_tags\_value\_case) | Org tag-value case policy (lower). Wire into provider "context" { tags\_value\_case = ... }. |
<!-- END_TF_DOCS -->
