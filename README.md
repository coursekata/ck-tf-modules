# CourseKata Shared IaC Library

**The org's shared, versioned library of reusable IaC building blocks** — the OpenTofu
modules, the reusable `tf-quality.yml` CI quality gate and `tf-renovate.yml` updater, and the `cloudposse/context`
labeling standard. Everything here is *composed into* a consuming repo at a pinned version
(`?ref=vX.Y.Z` / `@vX.Y.Z`), never deployed — the repo holds **no roots, no state, and no
applies**.

It is the **dependency root** of the org's IaC: every other repo (`ck-tooling`,
`ck-foundation`, `ck-datalake`, …) pins *into* it, it pins out at nothing, and it even lints
itself with its own quality gate. It is **public** so consumers fetch modules and call its CI
workflow with no token, and its `v*` tags are frozen immutable. It is a *sibling* of the
`ck-tooling` control plane, not part of it — the **repo-agnostic, credential-free** quality
bar lives here; the **AWS/OIDC-coupled** delivery gate (`tf-delivery.yml`) lives in
`ck-tooling`.

> **Where does a shared thing go?** Repo-agnostic and consumed by everyone → here.
> Coupled to AWS or the apply-gate → `ck-tooling`.

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
- **`README.md`** — what the module is for, how to use it, and the reasoning behind its seams. The variable and output blocks are the interface; read those.
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

## Quality gate (`tf-quality.yml`)

`pre-commit` (run via `prek`) and CI run fmt, validate, tflint, trivy, `tofu test`, and a
gitleaks secret scan on every change. Install the hooks once with `prek install`.

CI additionally runs two gates that a pre-commit hook cannot express, because a hook only ever
sees the staged diff: a **full-history committed-secret scan** (a secret committed and later
deleted is still disclosed to anyone who can clone) and a **dependency-CVE scan** over any
lockfile the repo declares. The local gitleaks hook prevents; these gate.

The same checks are packaged as the reusable **[`tf-quality.yml`](.github/workflows/tf-quality.yml)**
`workflow_call` — credential-free and repo-agnostic. This repo calls it locally; every other IaC
repo calls it remotely at a pinned tag (`uses: coursekata/ck-tf-modules/.github/workflows/tf-quality.yml@vX.Y.Z`),
so the org bar is defined once and `prek` keeps remote CI in parity with local pre-commit for the
hook-expressible checks. Bump a tool version here and all consumers inherit it.

### Local prerequisites

The hooks resolve these from `PATH`, so install them once (CI installs the same set at pinned
versions). Versions that must match CI are called out in `tf-quality.yml`.

| Tool | Why |
|------|-----|
| [`tofu`](https://opentofu.org) | fmt, validate, and `tofu test` |
| [`tflint`](https://github.com/terraform-linters/tflint) | lint |
| [`trivy`](https://trivy.dev) | misconfiguration scanning |
| [`gitleaks`](https://gitleaks.io) | secret detection |
| [`prek`](https://github.com/j178/prek) | the hook runner itself |

On macOS: `brew install opentofu tflint trivy gitleaks prek`.

## Dependency updates (`tf-renovate.yml` + `renovate/default.json`)

Renovate runs per repo, from one implementation. A consumer calls the reusable workflow at a pinned
tag and extends the shared preset:

```yaml
# .github/workflows/renovate.yml
on:
  schedule: [{ cron: "0 13 * * 1" }]
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
  issues: write
  statuses: write
jobs:
  renovate:
    uses: coursekata/ck-tf-modules/.github/workflows/tf-renovate.yml@vX.Y.Z
```

```json
// renovate.json
{ "extends": ["github>coursekata/ck-tf-modules//renovate/default.json"] }
```

Repo-specific rules sit alongside the `extends` — a custom manager for a version string that lives
outside any manifest, for instance.

**The workflow is pinned, the preset is not, and that split is deliberate.** A workflow executes
code, so it is pinned by tag and Dependabot moves the pin. The preset is declarative policy that
executes nothing, so it resolves from `main` and a change reaches the whole fleet at once — which is
the point of having one.

**It runs on each caller's own `GITHUB_TOKEN`**, not a central App. Pull requests authored that way
arrive with their CI held for a human to release; an App would fire those runs immediately, and no
App-side setting restores the gate. `statuses: write` is not optional — `minimumReleaseAge` is
enforced as a branch status, and without it Renovate creates the branch, fails silently, and reports
"Repository has changed during renovation" without ever opening the pull request.

Two things a repo-scoped token cannot do, which is why they are configured the way they are: it
cannot write under `.github/workflows`, so the `github-actions` manager stays off and Dependabot
keeps that ecosystem; and it cannot read Dependabot alerts, so vulnerability alerts surface through
Dependabot and CI's dependency gate rather than through Renovate.
