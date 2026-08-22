# s3-bucket

A hardened S3 bucket primitive for both org **security / audit buckets** (the CloudTrail archive,
a Config delivery bucket, …) and **ck-datalake tier buckets**. Always-on baseline: all four
public-access-block controls, TLS-only by default, versioning, SSE-S3. Optional: Object Lock
default retention, lifecycle expiry (bucket-wide or prefix-scoped), SSE-KMS — either consuming a
`kms_key_arn` or **creating its own CMK** (`create_kms`) and pinning uploads to it
(`require_sse_kms`), plus grants to **service OR AWS principals**.

Name + tags come from the **`cloudposse/context` provider** the consuming root configures; the
bucket is named in the org canonical order →
`ck-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]`. A single-env audit bucket
renders `ck-<domain>-<name>` (e.g. `ck-org-cloudtrail-logs`); a ck-datalake tier bucket
populates environment + surface to render `ck-datalake-stg-raw-app`. The wrong-account guard is
the **root's** job (the shared [`account-guard`](../account-guard) module), so this module takes
no `expected_account_id`.

> **`bucket_name_override`** is a deliberate escape hatch: set the bucket's literal name to adopt a
> **pre-existing, externally-referenced** bucket (a name baked into an asset/CDN URL or another
> system) that can't be renamed — i.e. to import it to no-diff. New buckets must leave it unset and
> take the convention name. The slot tags (`Domain`/`Environment`/…) still classify the bucket; only
> the id + `Name` tag take the literal value. (Pattern: `for_each` the module over a set of bucket
> names to create a fleet — e.g. the app's content/data/assets buckets, each with a cross-account
> write grant via `grants` + `principal_aws`.)

> The **ephemeral tier shape** (ck-datalake raw/staging/analytical) is this same module with
> `versioning_enabled = false`, `object_lock = null`, a per-tier `lifecycle_rule` (the analytical
> tier scopes `expiration_prefix = "_athena-results/"`), `create_kms = true` on the raw tier
> (RDS export needs a customer key) with `require_sse_kms = true`, and the `environment`/`surface`
> slots set per call. The CMK's key policy is attached by the caller via the `kms_key_id` output.

## Service-delivery grants

A log-delivery service (CloudTrail, Config, …) needs a bucket-policy statement allowing it to
write. Pass those as **`grants`** — ARN-free descriptions of *what to allow* — and the module
builds the single bucket policy by injecting the bucket's **own ARN** into each grant's resources.
Because a grant carries no bucket reference, a grant-producer module (e.g.
`cloudtrail-delivery-grant`) composes with this one **without depending on it**.

```hcl
provider "context" {
  # org labeling schema (typically from the context-schema module)
  values = { namespace = "ck", domain = "org" }
}

module "archive" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/s3-bucket?ref=v0.5.0"

  name       = "cloudtrail"
  attributes = "logs" # -> ck-org-cloudtrail-logs

  versioning_enabled = true
  object_lock        = { mode = "GOVERNANCE", retention_years = 3 }
  tls_only           = true

  # Grants are ARN-free; the module injects the bucket's own ARN. Shown inline here — in practice
  # a decoupled producer module (e.g. cloudtrail-delivery-grant) emits this same list.
  grants = [{
    sid               = "AllowCloudTrailWrite"
    principal_service = "cloudtrail.amazonaws.com"
    actions           = ["s3:PutObject"]
    key_suffixes      = ["/AWSLogs/123456789012/*"]
    conditions = [{
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }]
  }]
}
```

Each grant is `{ sid, principal_service | principal_aws, actions, key_suffixes, conditions }` —
exactly one principal: a **service** (`principal_service`, e.g. `cloudtrail.amazonaws.com`) or an
**AWS principal ARN** (`principal_aws`, e.g. a data-export role). `key_suffixes` are appended to
the bucket ARN — `""` = the bucket itself, `"/AWSLogs/<acct>/*"` = an object path.
