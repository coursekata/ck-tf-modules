# CourseKata OpenTofu Modules

The org's shared, hardened OpenTofu modules, consumed across CourseKata's IaC repos
(`ck-tooling`, `ck-foundation`, `ck-datalake`, …). This repo holds **no roots, no state,
and no applies** — modules are *consumed*, not deployed — so it carries only the PR-time
quality bar, not the delivery gate.

## Modules

| Module | Purpose |
|--------|---------|
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
configures it **once** (the org policy + that repo's namespace/tenant — see
[`docs/labeling-standard.md`](docs/labeling-standard.md)), then pins the module `source` to a
released **git tag** (Dependabot bumps the ref via PRs):

```hcl
# providers.tf — the org context (each repo sets its own namespace/tenant)
provider "context" {
  property_order  = ["namespace", "tenant", "stage", "name"]
  tags_value_case = "lower" # lowercase tag values (Title-case keys are the default)
  properties = {
    # validation_regex enforces lowercase: the provider doesn't auto-lowercase the id, so this
    # guards against invalid (uppercase) resource names.
    namespace = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    tenant    = { validation_regex = "^[a-z0-9-]*$" }
    stage     = { validation_regex = "^[a-z0-9-]*$" }
    name      = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = { namespace = "ck", tenant = "tooling" }
}

# main.tf — slots come from the provider; the module takes only its own inputs
module "state_backend" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/state-backend?ref=v0.1.0"

  expected_account_id = "123456789012"
}
```

`tofu init` fetches both the module (at that tag) and the `cloudposse/context` provider.

> **Private-repo access:** this repo is private, so any CI runner consuming it (and the
> dflook delivery actions) needs read access to it. Use a GitHub token with `repo:read`
> scoped to `coursekata/ck-tf-modules`, exposed to `tofu init` (e.g. a git `insteadOf`
> credential or `GITHUB_TOKEN` with the right permissions). See `docs/labeling-standard.md`.

## Versioning

SemVer via git tags (`vMAJOR.MINOR.PATCH`). A breaking change to a module's interface bumps
MAJOR; consumers pin a tag and upgrade deliberately.

## Quality bar

`pre-commit` (run via `prek`) and CI run fmt, validate, tflint, trivy, terraform-docs, and
`tofu test` on every change. Install the hooks once with `prek install`.
