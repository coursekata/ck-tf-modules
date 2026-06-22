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
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/s3-bucket?ref=v0.4.1"

  name       = "cloudtrail"
  attributes = "logs" # -> ck-org-cloudtrail-logs

  versioning_enabled = true
  object_lock        = { mode = "GOVERNANCE", retention_years = 3 }
  tls_only           = true

  # grants are usually produced by a dedicated grant module (decoupled, ARN-free):
  grants = module.cloudtrail_delivery_grant.grants
}
```

Each grant is `{ sid, principal_service | principal_aws, actions, key_suffixes, conditions }` —
exactly one principal: a **service** (`principal_service`, e.g. `cloudtrail.amazonaws.com`) or an
**AWS principal ARN** (`principal_aws`, e.g. a data-export role). `key_suffixes` are appended to
the bucket ARN — `""` = the bucket itself, `"/AWSLogs/<acct>/*"` = an object path.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.6, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.40 |
| <a name="requirement_context"></a> [context](#requirement\_context) | ~> 0.5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.40 |
| <a name="provider_context"></a> [context](#provider\_context) | ~> 0.5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [context_label.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | The context `name` slot for the bucket (e.g. "cloudtrail" -> ck-<domain>-cloudtrail). | `string` | n/a | yes |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | Optional context `attributes` slot, appended as a trailing qualifier (e.g. "logs" -> ...-cloudtrail-logs). "" renders no suffix. | `string` | `""` | no |
| <a name="input_bucket_name_override"></a> [bucket\_name\_override](#input\_bucket\_name\_override) | ESCAPE HATCH — the bucket's literal name, bypassing the context-rendered convention. Use ONLY<br/>to adopt a PRE-EXISTING, externally-referenced bucket (a name baked into an asset/CDN URL or<br/>another system) that cannot be renamed without breaking references — i.e. to import it to<br/>no-diff. NEW buckets must leave this "" and take the convention name. The classification still<br/>comes from the slots: `name` and the context provider still drive the Domain/Environment/Name/…<br/>tags; only the bucket id + its `Name` tag take this literal value. | `string` | `""` | no |
| <a name="input_create_kms"></a> [create\_kms](#input\_create\_kms) | Create a dedicated CMK + alias (alias/<rendered-id>) for this bucket and encrypt with it<br/>(SSE-KMS, bucket-key on; annual rotation; 30-day deletion window). The key's POLICY is left<br/>to the caller (attach an aws\_kms\_key\_policy referencing the kms\_key\_id/kms\_key\_arn outputs) so<br/>it can grant concrete principal ARNs. Use for a tier whose writer requires a customer key<br/>(e.g. the raw tier — RDS snapshot-export REQUIRES a CMK). Default false (SSE-S3 or<br/>kms\_key\_arn). Mutually exclusive with kms\_key\_arn. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Optional call-time `environment` slot override (e.g. "stg"/"prd"). Renders ck-<domain>-<environment>-…; "" leaves the provider's value (empty for single-env repos). Lets one provider config name buckets across environments. | `string` | `""` | no |
| <a name="input_grants"></a> [grants](#input\_grants) | Allow grants merged into the bucket's single policy (alongside tls\_only). Each grant becomes<br/>one Allow statement, and the bucket's OWN ARN is injected here — the resource is the bucket<br/>ARN plus each key\_suffix ("" = the bucket itself, "/AWSLogs/<acct>/*" = an object path). A<br/>grant carries NO bucket reference, so a grant-producer module (e.g. cloudtrail-delivery-grant)<br/>composes without depending on this one. Each grant names EXACTLY ONE principal: a service<br/>(principal\_service, e.g. "cloudtrail.amazonaws.com") OR an AWS principal (principal\_aws, a<br/>role/account ARN — e.g. a data-export role that writes to a tier bucket). | <pre>list(object({<br/>    sid               = string<br/>    principal_service = optional(string)             # a Service principal, e.g. "cloudtrail.amazonaws.com"<br/>    principal_aws     = optional(string)             # OR an AWS principal ARN, e.g. an IAM role<br/>    actions           = list(string)                 # e.g. ["s3:PutObject"]<br/>    key_suffixes      = optional(list(string), [""]) # appended to the bucket ARN; "" = bare bucket<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for SSE-KMS using an EXISTING key. null uses SSE-S3 (AES256). Mutually exclusive with create\_kms (which makes the bucket its own key). | `string` | `null` | no |
| <a name="input_lifecycle_rule"></a> [lifecycle\_rule](#input\_lifecycle\_rule) | Optional lifecycle knobs on a single all-objects rule. Any null field omits that<br/>action; if the object itself is null (or every field is null) no lifecycle<br/>configuration is created (lets a bucket import to no-diff against one with none). | <pre>object({<br/>    expiration_days                    = optional(number)<br/>    noncurrent_version_expiration_days = optional(number)<br/>    abort_incomplete_multipart_days    = optional(number)<br/>    expiration_prefix                  = optional(string, "") # "" = bucket-wide; set to scope expiry to a key prefix (e.g. "_athena-results/")<br/>  })</pre> | `null` | no |
| <a name="input_object_lock"></a> [object\_lock](#input\_object\_lock) | S3 Object Lock default retention, or null to create the bucket without Object Lock.<br/>Set exactly one of retention\_years / retention\_days. Requires versioning\_enabled.<br/>GOVERNANCE allows privileged bypass (break-glass); COMPLIANCE allows none. | <pre>object({<br/>    mode            = string<br/>    retention_years = optional(number)<br/>    retention_days  = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_object_ownership"></a> [object\_ownership](#input\_object\_ownership) | S3 Object Ownership. Defaults to BucketOwnerEnforced (ACLs disabled — the recommended<br/>posture for a durable audit bucket). Set null to leave ownership unmanaged, e.g. when<br/>importing an existing bucket to no-diff that has no explicit ownership-controls config. | `string` | `"BucketOwnerEnforced"` | no |
| <a name="input_require_sse_kms"></a> [require\_sse\_kms](#input\_require\_sse\_kms) | When the bucket has a CMK (create\_kms or kms\_key\_arn), add two Deny statements to the bucket<br/>policy that refuse any PutObject not encrypted with SSE-KMS pinned to THIS bucket's key<br/>(DenyNonKmsUploads + DenyWrongKmsKey, StringNotEqualsIfExists — a header-less upload is denied,<br/>not defaulted). Inert without a CMK. Default false (no upload-encryption invariant). | `bool` | `false` | no |
| <a name="input_surface"></a> [surface](#input\_surface) | Optional call-time `surface` slot override (e.g. a datalake tier "raw"/"staging"/"analytical"). Renders …-<surface>-<name>; "" leaves the provider's value. Lets one provider config name buckets across surfaces/tiers. | `string` | `""` | no |
| <a name="input_tls_only"></a> [tls\_only](#input\_tls\_only) | Attach a bucket-policy statement denying non-TLS (aws:SecureTransport=false) access. | `bool` | `true` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Enable S3 versioning. Must be true when object\_lock is set. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | Bucket ARN. |
| <a name="output_bucket_domain_name"></a> [bucket\_domain\_name](#output\_bucket\_domain\_name) | Bucket regional domain name. |
| <a name="output_id"></a> [id](#output\_id) | Bucket name / id. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the bucket's created CMK (create\_kms), else null. Wire into an aws\_kms\_key\_policy to grant concrete principals, or reference for SSE-KMS-pinned writes. |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | The created CMK's key id (null when create\_kms is false) — pass as aws\_kms\_key\_policy.key\_id to attach the key's policy. |
<!-- END_TF_DOCS -->
