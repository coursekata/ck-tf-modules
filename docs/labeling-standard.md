# Labeling & tagging standard

The org standardizes resource **naming and tagging** on the **`cloudposse/context`
provider** (pinned `~> 0.5.0`). There is no vendored `context.tf` and no `null-label`
module — every repo configures the provider once and modules derive names/tags from it.

## The standard provider block

Each root configures the `context` provider with the org policy plus its own
namespace/tenant. Copy this into the root's `providers.tf` and set `values`:

```hcl
provider "context" {
  # Org policy — identical across repos:
  tags_value_case = "lower" # lowercase tag values; Title-case keys are the default
  property_order  = ["namespace", "tenant", "stage", "name"]
  properties = {
    # validation_regex enforces lowercase — see "Casing & enforcement" below.
    namespace = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    tenant    = { validation_regex = "^[a-z0-9-]*$" }
    stage     = { validation_regex = "^[a-z0-9-]*$" }
    name      = { validation_regex = "^[a-z0-9-]*$" }
  }

  # Per-repo — set these to the repo's tenant:
  values = {
    namespace = "ck"
    tenant    = "tooling" # tooling | org | research-internal | ...
  }
}
```

`property_order`/`properties` vary per repo (ck-datalake adds `environment` + `attributes`);
the **invariants below are org-wide** so tags stay consistent across every repo.

## Casing & enforcement

- **Tag keys are Title-case** (`Namespace`, `Tenant`, `Stage`, …) — the provider default.
- **Tag values are lowercase** via `tags_value_case = "lower"`.
- **IDs are NOT auto-lowercased** by the provider (unlike the old null-label). Since S3 bucket
  names must be lowercase, every property carries a lowercase `validation_regex` so a
  mixed-case value **fails the plan loudly** instead of producing an invalid name.
- **`Name` tag = the full id** — modules pin `Name = <rendered>` (the useful AWS convention),
  not the bare `name` value.
- **`Owner`/`Repo`/`ManagedBy`** are NOT label slots — set them once per root via the AWS
  provider's `default_tags`.

And declare the provider in `versions.tf`:

```hcl
terraform {
  required_providers {
    context = { source = "cloudposse/context", version = "~> 0.5.0" }
  }
}
```

## Slots

| Slot | Meaning | Examples |
|------|---------|----------|
| `namespace` | org — always `ck`, always present (enforced) | `ck` |
| `tenant` | the repo's domain discriminator | `tooling`, `org`, `research-internal` |
| `stage` | optional lifecycle/tier; empty drops out | `prd`, `stg` |
| `name` | the component | `tfstate`, `hub` |
| `attributes` | trailing role qualifiers | `oidc`, `plan` |

Names render as `<namespace>-<tenant>[-<stage>]-<name>[-<attributes>]`, e.g.
`ck-tooling-tfstate`, `ck-org-tfstate`, `ck-research-internal-prd-tfstate`.

## Per-repo values

| Repo | `tenant` | example bucket |
|------|----------|----------------|
| ck-tooling | `tooling` | `ck-tooling-tfstate` |
| ck-foundation | `org` | `ck-org-tfstate` |
| ck-datalake | `research-internal` (+ `stage`) | `ck-research-internal-prd-tfstate` |

## How modules use it

Modules read `data "context_label"` (names) and `data "context_tags"` (tags) — the
consuming root's provider config supplies the slot values. A module **may pin its own
`property_order`** for a stable resource-name structure regardless of the root's order
(e.g. `state-backend` pins `["namespace","tenant","stage","name"]` so a threaded pipeline
order can't rename a state bucket). Modules also pin the **`Name` tag to the full id**
(not the bare `name`), the useful AWS convention.

## Adoption status

- **ck-tooling** — adopting; a no-op switch (same `ck-tooling-tfstate`, same tags).
- **ck-foundation** — migrating off hand-stitched `Namespace`/`Tenant` tags onto this.
- **ck-datalake** — to be reworked onto the provider; its 6-slot pipeline labels map directly
  (add `environment` + `attributes` to `property_order`/`properties`, keep its order
  `[namespace, tenant, environment, name, stage, attributes]`), with one call-site change:
  the provider's `values` are `map(string)` (no list type), so keep the attributes list in
  the caller and join at the boundary — `attributes = join("-", ["snapshot-export-trigger",
  "dlq"])`. Glue databases keep their `_` delimiter via the per-label `delimiter` input.
  Output IDs/tags are byte-identical to today's null-label results.

## Notes

- **Pinned `~> 0.5.0`** — the provider is pre-1.0, so we ride 0.5.x patches but never
  auto-jump to 0.6; Dependabot proposes patch bumps (an `ignore` rule blocks minor/major).
  `null-label` is pre-1.0 too,
  so this is no riskier than what it replaces.
