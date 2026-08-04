# Labeling & tagging standard

The org standardizes resource **naming and tagging** on the **`cloudposse/context`
provider** (pinned `~> 0.5.0`). There is no vendored `context.tf` and no `null-label`
module — every repo configures the provider once and modules derive names/tags from it.

The canonical order is **one, org-wide**:

```
ck-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]
```

Bracketed slots are optional: empty slots render away, so a single-env/single-surface repo
gets `ck-<domain>-<name>` while ck-datalake's tier resources get the full
`ck-datalake-stg-raw-app`.

## The standard provider block

Each root configures the `context` provider with the org policy plus its own values. The schema
half (everything except `values`) is emitted by the [`context-schema`](../modules/context-schema)
module, so a root pulls it instead of hand-copying. Set only `values`:

```hcl
provider "context" {
  # Org policy — identical across repos (sourced from the context-schema module):
  property_order  = module.context_schema.property_order  # [namespace, domain, environment, surface, name, attributes]
  properties      = module.context_schema.properties
  tags_value_case = module.context_schema.tags_value_case # lower

  # Per-repo — set the slots this repo populates:
  values = {
    namespace = "ck"
    domain    = "tooling" # tooling | org | datalake | app | canvas | content
    # environment / surface — set only by multi-env / multi-surface repos (e.g. ck-datalake)
  }
}
```

Hand-rolled equivalent (what `context-schema` emits), for reference:

```hcl
property_order = ["namespace", "domain", "environment", "surface", "name", "attributes"]
properties = {
  # validation_regex enforces lowercase — see "Casing & enforcement" below.
  namespace   = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
  domain      = { validation_regex = "^[a-z0-9-]*$" }
  environment = { validation_regex = "^[a-z0-9-]*$" }
  surface     = { validation_regex = "^[a-z0-9-]*$" }
  name        = { validation_regex = "^[a-z0-9-]*$" }
  attributes  = { validation_regex = "^[a-z0-9-]*$" }
}
```

Every root declares the **full property union** even if it renders only a subset — each
`data.context_label` picks its own slots, so a wider schema never changes a rendered id but
keeps every provider block identical.

## Casing & enforcement

- **Tag keys are Title-case** (`Namespace`, `Domain`, `Environment`, `Surface`, `Name`,
  `Attributes`) — the provider default.
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
| `domain` | the product/system a repo owns | `org`, `tooling`, `datalake`, `app`, `canvas`, `content` |
| `environment` | deploy environment; empty for a singleton | `stg`, `prd`, `dev`, `pr-1234` |
| `surface` | within-domain subdivision; empty when the domain has one | data tiers `raw`/`staging`/`intermediate`/`marts`/`analytical` (datalake); interface surfaces `api`/`web`/`mobile` (app) |
| `name` | the resource's primary identity within (domain, env, surface) | `tfstate`, `cloudtrail`, `deploy`, `app` (source system) |
| `attributes` | trailing role qualifiers | `plan`, `logs`, `writer` |

`surface` generalizes the "which part of the domain" axis: it reads as both "the analytical
**surface** of the lake" and "the web **surface** of the app." The frontend is **not** a peer
domain — it is `domain=app, surface=web`; the backend is `domain=app, surface=api`.

Names render as `ck-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]`, e.g.
`ck-tooling-tfstate`, `ck-org-cloudtrail-logs`, `ck-datalake-stg-raw-app`,
`ck-app-api-deploy-plan`.

## Per-repo values

| Repo | `domain` | sets `environment`/`surface`? | example id |
|------|----------|-------------------------------|------------|
| ck-tooling | `tooling` | no | `ck-tooling-tfstate` |
| ck-foundation | `org` | no | `ck-org-cloudtrail-logs` |
| ck-datalake | `datalake` | yes (env = source-env-class, surface = data tier) | `ck-datalake-stg-raw-app` |
| app backend (future) | `app` | surface=`api` (env per deploy) | `ck-app-api-deploy` |
| app frontend (future) | `app` | surface=`web` | `ck-app-web-deploy` |
| canvas (future) | `canvas` | no (surface only if Canvas hosting lands) | `ck-canvas-ses` |

The **state bucket is one per domain and deliberately env-less/surface-less**:
`ck-<domain>-tfstate` (e.g. `ck-tooling-tfstate`, `ck-datalake-tfstate`). The `state-backend`
module lists the full canonical order, but the bootstrap root that owns the bucket simply does
not populate `environment`/`surface`, so the env/surface slots drop and the one bucket holds
every root's state.

## How modules use it

Modules read `data "context_label"` (names) and `data "context_tags"` (tags) — the consuming
root's provider config supplies the slot values. A module **pins its own `properties` list** for
a stable resource-name structure regardless of the root's default order, always in the canonical
order so a slot can never land in the wrong position (e.g. `state-backend` pins
`["namespace","domain","environment","surface","name"]`; `s3-bucket` adds `attributes`). Modules
also pin the **`Name` tag to the full id** (not the bare `name`), the useful AWS convention.

## Adoption status

- **ck-tooling** — adopted; `domain=tooling`, single-env (`ck-tooling-*`).
- **ck-foundation** — adopted; `domain=org`, single-env (`ck-org-*`).
- **ck-datalake** — migrating onto the provider with `domain=datalake` and populated
  `environment` (source-env-class) + `surface` (data tier). Its tier resources render
  `ck-datalake-<env>-<tier>-<name>` (name = source system for data resources, source-less
  component for shared infra). Glue databases keep their `_` delimiter via the per-label
  `delimiter` input.

## Notes

- **Pinned `~> 0.5.0`** — the provider is pre-1.0, so we ride 0.5.x patches but never
  auto-jump to 0.6; Dependabot proposes patch bumps (an `ignore` rule blocks minor/major).
  `null-label` was pre-1.0 too, so this is no riskier than what it replaces.
- **Vocabulary changes are breaking.** Renaming or reordering a slot changes tag keys (and can
  change ids), so it lands as a module **minor** release (0.x convention: minor = breaking) and
  every consumer re-pins deliberately. The `v0.4.0` rename (`tenant→domain`, `stage→surface`,
  `+environment`) kept all then-current ids byte-identical and changed only tag keys.
