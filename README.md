# CourseKata Shared IaC Library

The org's shared, versioned library of OpenTofu modules and the `cloudposse/context` labeling standard. Everything here is composed into a consuming repo at a pinned tag (`?ref=vX.Y.Z`) and never deployed: the repo holds no roots, no state and no applies.

It is public, so consumers fetch modules with no token, and its `v*` tags are frozen. Every IaC repo pins modules from it. The CI pieces other repositories' workflows call, including the quality bar this repo runs on itself, live in [ck-ci](https://github.com/coursekata/ck-ci), which pins nothing here, so neither repository's release waits on the other's.

> **Where does a shared thing go?** An OpenTofu module goes here. Anything another repository's CI calls goes in ck-ci. Account-specific orchestration and the apply gate live in `ck-tooling`.

## Modules

| Module | Purpose |
|--------|---------|
| [`account-guard`](modules/account-guard) | Root-preamble guard: asserts the running credential resolves to the expected account and fails the plan otherwise. Every root calls it once per provider. |
| [`context-schema`](modules/context-schema) | Outputs-only module emitting the org labeling schema (property order, slots, tag-case) that each root's `cloudposse/context` provider is configured from. |
| [`deploy-roles`](modules/deploy-roles) | Spoke plan (RO) + apply (RW) IAM roles for the OIDC hub-spoke delivery model — standardized trust, caller-supplied permissions. |
| [`ecr-image-publisher`](modules/ecr-image-publisher) | Protected-branch GitHub OIDC role for publishing reviewed images to ECR, with live permission checks. |
| [`ecr-image-pipeline`](modules/ecr-image-pipeline) | Candidate, release and cache ECR repositories per image, with a default-branch build role, a pull-request cache-read role, a release-environment role and a release-read role per consumer, for the image pipeline. |
| [`ecr-repo`](modules/ecr-repo) | Immutable ECR repository with candidate-age or release-count retention. |
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

## Quality gate

`ci.yml` runs the org's quality bar, ck-ci's [`tf-quality.yml`](https://github.com/coursekata/ck-ci/blob/main/.github/workflows/tf-quality.yml), at a release tag: fmt, validate, tflint, trivy and `tofu test` in every module, plus a full-history secret scan and a dependency CVE scan. Its `hooks` job runs this repository's own pre-commit hooks, skipping the ones the bar runs. Install the hooks once with `prek install`; they run the bar's checks locally as well.

## Image delivery

`modules/ecr-image-pipeline` provides the ECR side of the image pipeline, whose shared workflow and contract live in ck-ci ([`image/README.md`](https://github.com/coursekata/ck-ci/blob/main/image/README.md)).

The earlier lane, in which the protected branch rebuilds reviewed source ([`docs/image-delivery.md`](docs/image-delivery.md)), stays until no repository pins it.

### Local prerequisites

The hooks resolve these from `PATH`, so install them once (CI installs the same set at pinned
versions). Versions that must match CI are called out in ck-ci's `tf-quality.yml`.

| Tool | Why |
|------|-----|
| [`tofu`](https://opentofu.org) | fmt, validate, and `tofu test` |
| [`tflint`](https://github.com/terraform-linters/tflint) | lint |
| [`trivy`](https://trivy.dev) | misconfiguration scanning |
| [`gitleaks`](https://gitleaks.io) | secret detection |
| [`prek`](https://github.com/j178/prek) | the hook runner itself |

On macOS: `brew install opentofu tflint trivy gitleaks prek`.

## Dependency updates

Renovate runs here as the hosted App and extends ck-ci's preset; Dependabot keeps the action SHAs in `ci.yml` current. ck-ci's README describes the preset and the self-hosted workflow the spokes run.
