# state-backend

A reusable, hardened S3 bucket for backing an OpenTofu root's state via the
OpenTofu 1.11+ **native S3 lockfile** (`use_lockfile = true` in the consuming
root's `backend.tf` — no DynamoDB table).

Bucket name + tags come from the **`cloudposse/context` provider** (pinned `~> 0.5.0`),
which the **consuming root configures** with the org policy and its namespace/tenant; the
module just sets `name = "tfstate"` and pins the state-bucket property order, yielding
`<namespace>-<tenant>[-<stage>]-tfstate`. The bucket is **pinned to `expected_account_id`**:
a precondition fails the plan if the provider resolved to a different account, so a
wrong-profile apply can never create state in the wrong place.

Hardening: versioning on, all four public-access-block controls on, SSE-S3
(AES256) by default, a `DenyInsecureTransport` (TLS-only) bucket policy, and a
lifecycle rule expiring noncurrent versions after `noncurrent_version_expiration_days`.

## Usage — self-hosting bootstrap (two steps)

This module creates the very bucket that backs OpenTofu state — so the root that
calls it faces a chicken-and-egg: it can't store its own state in a bucket that
doesn't exist yet. The fix is a **two-step bootstrap**: first `apply` the module
with a **local** backend to create the bucket, then point a `backend.tf` at that
bucket and **migrate** the local state into it. After that the root self-hosts and
the local state file is thrown away.

> Roots that merely *consume* an already-created bucket (e.g. a sibling
> `environments/<env>/`) skip all of this — they just add a `backend.tf` with the
> bucket name and their own distinct `key`. Only the bootstrap root that *owns* the
> bucket does the migrate.

### Step 1 — create the bucket (local state)

In the bootstrap root, configure the **`context` provider** (org policy + this repo's
namespace/tenant), call the module, and **re-export `bucket_name`**. Do **not** add a
`backend.tf` yet.

```hcl
# providers.tf — the org context (each repo sets its own namespace/tenant)
provider "context" {
  property_order = ["namespace", "tenant", "stage", "name"]
  properties     = { namespace = { required = true, min_length = 1 }, tenant = {}, stage = {}, name = {} }
  values         = { namespace = "ck", tenant = "tooling" } # → bucket "ck-tooling-tfstate"
}

# main.tf — namespace/tenant come from the provider, not the module
module "state_backend" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/state-backend?ref=v0.1.0"

  expected_account_id = "123456789012" # provider MUST resolve here or the plan fails
}

# outputs.tf
output "bucket_name" { value = module.state_backend.bucket_name }
```

Authenticate to `expected_account_id`, then create the bucket. State is local at
this point:

```sh
tofu init        # local backend
tofu apply       # creates the hardened bucket
```

### Step 2 — read the output, write `backend.tf`, migrate

Read the bucket name the module produced:

```sh
tofu output -raw bucket_name        # → ck-tooling-tfstate
```

Backend blocks can't take variables, so write the values as **literals**. `bucket`
must equal the output above; choose a `key` that is unique within the bucket if it
backs more than one root (the hub uses `hub/terraform.tfstate`):

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket       = "ck-tooling-tfstate"
    key          = "bootstrap/state-backend/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true   # native S3 locking, no DynamoDB (OpenTofu ≥ 1.11)
  }
}
```

Migrate the local state into the bucket, then verify and stop tracking the local
file:

```sh
tofu init -migrate-state            # answer "yes" to copy state up
# non-interactive equivalent: tofu init -migrate-state -force-copy

tofu state list                     # now served from S3
tofu plan                           # MUST report: No changes
git rm --cached terraform.tfstate   # if the local state was ever committed; then
                                    # drop any .gitignore exception that un-ignored it
```

**Caveat — `-force-copy` resets state metadata.** It copies the resource content
faithfully (a `tofu plan` no-op confirms it), but writes the migrated state with a
**fresh `lineage`/`serial`**. Your pre-migration local snapshot therefore has a
different lineage, so a later `tofu state push` of it would need `-force`. Keep the
local `terraform.tfstate.backup` until you've confirmed the S3 copy with a clean
plan.

### Refresher (already-bootstrapped root)

Minimal call once the bucket and `backend.tf` already exist (namespace/tenant come from the
root's `context` provider):

```hcl
module "state_backend" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/state-backend?ref=v0.1.0"

  expected_account_id = "123456789012"
}
```

## Pointing downstream roots at this bucket

The module is called **once per repo/tenant** (from `bootstrap/state-backend/`) and
creates exactly one bucket — `<namespace>-<tenant>-tfstate` from the `context` provider,
e.g. `ck-tooling-tfstate`. That single bucket holds the state of **every** root in the
repo, not just the bootstrap root that owns it.

A sibling/downstream root (e.g. `environments/hub/`) does **not** re-run this module,
create another bucket, or migrate. It just adds a `backend.tf` pointing at the
already-existing bucket with its **own unique `key`**:

- `bucket` = this module's `bucket_name` output (`ck-tooling-tfstate`), written as a
  literal — backend blocks can't take variables.
- `key` = the root's path/name plus `/terraform.tfstate` (e.g. `environments/hub` →
  `hub/terraform.tfstate`; the bootstrap root → `bootstrap/state-backend/terraform.tfstate`).
  It only has to be **unique within the bucket**.

```hcl
# environments/hub/backend.tf
terraform {
  backend "s3" {
    bucket       = "ck-tooling-tfstate"     # = modules/state-backend bucket_name output
    key          = "hub/terraform.tfstate"  # unique within the bucket
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true   # native S3 locking, no DynamoDB (OpenTofu ≥ 1.11)
  }
}
```

Only `key` changes between roots in the same bucket; `region`/`encrypt`/`use_lockfile`
are identical. A root that manages resources in a **different account** than the bucket
sets its own `region` and adds an `assume_role` block to the backend — but `bucket`
still equals this module's output and `key` is still unique.

> **Warning:** the `key` is the only thing keeping roots apart. Reuse a `key` and two
> roots write the same state object — each `apply` clobbers the other's state.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.6, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |
| <a name="requirement_context"></a> [context](#requirement\_context) | ~> 0.5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |
| <a name="provider_context"></a> [context](#provider\_context) | ~> 0.5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.tls_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.tfstate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.tls_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [context_label.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_expected_account_id"></a> [expected\_account\_id](#input\_expected\_account\_id) | AWS account the bucket must be created in. A precondition fails the plan if the provider resolves to a different account, so a wrong-profile apply can't land the bucket elsewhere. | `string` | n/a | yes |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Days to retain noncurrent object versions before expiry. Versioning keeps state history; this bounds how long superseded versions accumulate. | `number` | `90` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the state bucket. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name (and id) of the state bucket. Wire into a consuming root's backend.tf `bucket`. |
<!-- END_TF_DOCS -->
