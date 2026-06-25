# CourseKata OpenTofu Modules

The org's shared, hardened OpenTofu modules, consumed across CourseKata's IaC repos
(`ck-tooling`, `ck-foundation`, `ck-datalake`, …). This repo holds **no roots, no state,
and no applies** — modules are *consumed*, not deployed — so it carries only the PR-time
quality bar, not the delivery gate.

## Modules

| Module | Purpose |
|--------|---------|
| [`account-guard`](modules/account-guard) | Root-preamble guard: asserts the running credential resolves to the expected account and fails the plan otherwise. Every root calls it once per provider. |
| [`context-schema`](modules/context-schema) | Outputs-only module emitting the org labeling schema (property order, slots, tag-case) that each root's `cloudposse/context` provider is configured from. |
| [`deploy-roles`](modules/deploy-roles) | Spoke plan (RO) + apply (RW) IAM roles for the OIDC hub-spoke delivery model — standardized trust, caller-supplied permissions. |
| [`log-group`](modules/log-group) | CloudWatch Logs log-group primitive — context-rendered name/tags, an optional AWS-mandated source prefix, and a caller-chosen retention. The logging sibling of `s3-bucket`. |
| [`s3-bucket`](modules/s3-bucket) | Hardened, durable S3 bucket archetype for security/audit buckets, with a generic ARN-free `grants` seam for service-delivery policies. |
| [`state-backend`](modules/state-backend) | Hardened S3 bucket backing an OpenTofu root's state via the native S3 lockfile (no DynamoDB). |

## Layout

Each module lives in `modules/<name>/` and contains:

- **`main.tf`** — the module's resources and data sources.
- **`variables.tf`** — input variables, with validations.
- **`outputs.tf`** — values consumers wire into their config.
- **`versions.tf`** — `required_version` and `required_providers` constraints.
- **`README.md`** — usage notes plus the terraform-docs-generated input/output tables.
- **`tests/`** — native `tofu test` suites (`*.tftest.hcl`).

Modules configure **no provider** — the consuming root supplies it (and its `default_tags`).

## Consuming a module

Modules derive names/tags from the **`cloudposse/context` provider**, so a consuming root
configures it **once**: the org schema comes from the [`context-schema`](modules/context-schema)
module (canonical spec: [`docs/labeling-standard.md`](docs/labeling-standard.md)), and the root
supplies only its namespace/domain. Module `source`s pin a released **git tag** (Dependabot bumps
the ref via PRs):

```hcl
# providers.tf — configure the context provider from the context-schema module.
module "context_schema" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/context-schema?ref=v0.4.0"
}

provider "context" {
  property_order  = module.context_schema.property_order
  properties      = module.context_schema.properties
  tags_value_case = module.context_schema.tags_value_case
  values          = { namespace = "ck", domain = "tooling" } # each repo sets its own
}

# main.tf — every root guards its account first, then calls its modules (slots come from the provider)
module "account_guard" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/account-guard?ref=v0.4.0"

  expected_account_id = "123456789012"
}

module "state_backend" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/state-backend?ref=v0.4.0"
}
```

`tofu init` fetches the modules (at their tags) and the `cloudposse/context` provider.

## Versioning

SemVer via git tags (`vMAJOR.MINOR.PATCH`); consumers pin a tag and upgrade deliberately.
**While pre-1.0 (`0.y.z`)** the MINOR is the breaking/compatibility signal and the PATCH covers
additive changes *and* features — adding a module is a **patch** bump (e.g. `v0.2.1` → `v0.2.2`).
At `1.0.0`, MINOR returns to "new backward-compatible feature" and MAJOR signals a break. (The
SemVer spec leaves 0.x minor/patch meaning undefined; this convention matches Terraform's own
`~> 0.y.z` constraint behaviour.)

## Quality bar

`pre-commit` (run via `prek`) and CI run fmt, validate, tflint, trivy, terraform-docs, and
`tofu test` on every change. Install the hooks once with `prek install`.
