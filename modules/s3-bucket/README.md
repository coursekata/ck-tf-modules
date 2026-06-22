# s3-bucket

A hardened, durable S3 bucket primitive for org **security / audit buckets** (the CloudTrail
archive, a Config delivery bucket, …). Always-on baseline: all four public-access-block controls,
TLS-only by default, versioning, SSE-S3. Optional: Object Lock default retention, lifecycle
expiry, SSE-KMS.

Name + tags come from the **`cloudposse/context` provider** the consuming root configures; the
bucket is named in the org canonical order →
`ck-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]`. A single-env audit bucket
renders `ck-<domain>-<name>` (e.g. `ck-org-cloudtrail-logs`); a ck-datalake tier bucket
populates environment + surface to render `ck-datalake-stg-raw-app`. The wrong-account guard is
the **root's** job (the shared [`account-guard`](../account-guard) module), so this module takes
no `expected_account_id`.

> Not ck-datalake's tier-bucket (ephemeral: always-KMS, versioning off, no Object Lock). Different
> trust/retention model — do not conflate.

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
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/s3-bucket?ref=v0.4.0"

  name       = "cloudtrail"
  attributes = "logs" # -> ck-org-cloudtrail-logs

  versioning_enabled = true
  object_lock        = { mode = "GOVERNANCE", retention_years = 3 }
  tls_only           = true

  # grants are usually produced by a dedicated grant module (decoupled, ARN-free):
  grants = module.cloudtrail_delivery_grant.grants
}
```

Each grant is `{ sid, principal_service, actions, key_suffixes, conditions }`. `key_suffixes` are
appended to the bucket ARN — `""` = the bucket itself, `"/AWSLogs/<acct>/*"` = an object path.

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
| <a name="input_grants"></a> [grants](#input\_grants) | Service-delivery grants merged into the bucket's single policy (alongside tls\_only). Each<br/>grant becomes one Allow statement, and the bucket's OWN ARN is injected here — the resource<br/>is the bucket ARN plus each key\_suffix ("" = the bucket itself, "/AWSLogs/<acct>/*" = an<br/>object path). A grant carries NO bucket reference, so a grant-producer module (e.g.<br/>cloudtrail-delivery-grant) composes without depending on this one. | <pre>list(object({<br/>    sid               = string<br/>    principal_service = string                       # e.g. "cloudtrail.amazonaws.com"<br/>    actions           = list(string)                 # e.g. ["s3:PutObject"]<br/>    key_suffixes      = optional(list(string), [""]) # appended to the bucket ARN; "" = bare bucket<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for SSE-KMS. null uses SSE-S3 (AES256), the default until a key-management driver exists. | `string` | `null` | no |
| <a name="input_lifecycle_rule"></a> [lifecycle\_rule](#input\_lifecycle\_rule) | Optional lifecycle knobs on a single all-objects rule. Any null field omits that<br/>action; if the object itself is null (or every field is null) no lifecycle<br/>configuration is created (lets a bucket import to no-diff against one with none). | <pre>object({<br/>    expiration_days                    = optional(number)<br/>    noncurrent_version_expiration_days = optional(number)<br/>    abort_incomplete_multipart_days    = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_object_lock"></a> [object\_lock](#input\_object\_lock) | S3 Object Lock default retention, or null to create the bucket without Object Lock.<br/>Set exactly one of retention\_years / retention\_days. Requires versioning\_enabled.<br/>GOVERNANCE allows privileged bypass (break-glass); COMPLIANCE allows none. | <pre>object({<br/>    mode            = string<br/>    retention_years = optional(number)<br/>    retention_days  = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_object_ownership"></a> [object\_ownership](#input\_object\_ownership) | S3 Object Ownership. Defaults to BucketOwnerEnforced (ACLs disabled — the recommended<br/>posture for a durable audit bucket). Set null to leave ownership unmanaged, e.g. when<br/>importing an existing bucket to no-diff that has no explicit ownership-controls config. | `string` | `"BucketOwnerEnforced"` | no |
| <a name="input_tls_only"></a> [tls\_only](#input\_tls\_only) | Attach a bucket-policy statement denying non-TLS (aws:SecureTransport=false) access. | `bool` | `true` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Enable S3 versioning. Must be true when object\_lock is set. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | Bucket ARN. |
| <a name="output_bucket_domain_name"></a> [bucket\_domain\_name](#output\_bucket\_domain\_name) | Bucket regional domain name. |
| <a name="output_id"></a> [id](#output\_id) | Bucket name / id. |
<!-- END_TF_DOCS -->
