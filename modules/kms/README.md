# kms

A customer-managed **KMS key** primitive: a context-rendered alias, annual rotation, a bounded
deletion window, and a key policy of the always-on **root-account administration** statement plus a
caller-supplied **grants** seam. One module so the CMK hardening baseline (rotation on, a root-admin
statement so the key is never orphaned) doesn't drift between the org's bespoke keys.

Name + tags come from the **`cloudposse/context` provider** the consuming root configures; the alias
is `alias/ck-<domain>[-<environment>][-<surface>]-<name>[-<attributes>]`. The account-root principal
in the policy is derived from `aws_caller_identity` — never hand-passed.

The **`grants`** seam mirrors [`s3-bucket`](../s3-bucket): each grant is one Allow statement naming
**exactly one** principal — a service (`principal_service`) OR an AWS role/account ARN
(`principal_aws`) — with its KMS actions and optional conditions. Put an `aws:SourceAccount`
condition on service grants (confused-deputy defense). A key policy's resource is always the key
itself, so it is fixed to `*` here.

## Usage

```hcl
# A CD delivery CMK shared by the artifact bucket + the notification SNS topic.
module "cd_kms" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/kms?ref=v0.5.2"

  # slots (environment/surface/name/…) come from the root context provider

  grants = [
    {
      sid               = "AllowEventBridgeEncryptForSns"
      principal_service = "events.amazonaws.com"
      actions           = ["kms:GenerateDataKey*", "kms:Decrypt"]
      conditions        = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
    },
    {
      sid           = "AllowCodeBuildReadArtifacts"
      principal_aws = module.codebuild_apply_role.arn
      actions       = ["kms:Decrypt", "kms:GenerateDataKey"]
    },
  ]
}
```

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
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [context_label.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | Optional `attributes` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Days before a scheduled key deletion completes (7-30). Default 30 — the maximum recovery window. | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Optional key description. "" (default) renders "CMK for <rendered-id>.". | `string` | `""` | no |
| <a name="input_enable_key_rotation"></a> [enable\_key\_rotation](#input\_enable\_key\_rotation) | Enable annual automatic key rotation. Default true (the org baseline). | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Optional `environment` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |
| <a name="input_grants"></a> [grants](#input\_grants) | Allow grants merged into the key policy alongside the always-on root-account administration<br/>statement. Each grant becomes one Allow statement whose resource is the key itself ("*" in a<br/>key policy). Name EXACTLY ONE principal per grant: a service (principal\_service, e.g.<br/>"cloudwatch.amazonaws.com" or "chatbot.amazonaws.com") OR an AWS principal (principal\_aws, a<br/>role/account ARN — e.g. a CodeBuild or CodePipeline service role that must GenerateDataKey /<br/>Decrypt to read an SSE-KMS artifact). Add an aws:SourceAccount condition on service grants for<br/>confused-deputy defense. | <pre>list(object({<br/>    sid               = string<br/>    principal_service = optional(string) # a Service principal, e.g. "events.amazonaws.com"<br/>    principal_aws     = optional(string) # OR an AWS principal ARN, e.g. an IAM role<br/>    actions           = list(string)     # e.g. ["kms:GenerateDataKey*", "kms:Decrypt"]<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | The `name` slot. Defaults to "kms"; override per key (the key alias is alias/<rendered-id>). | `string` | `"kms"` | no |
| <a name="input_surface"></a> [surface](#input\_surface) | Optional `surface` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | The key alias ARN. |
| <a name="output_alias_name"></a> [alias\_name](#output\_alias\_name) | The key alias name (alias/<rendered-id>). |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | The CMK ARN. Wire into aws\_sns\_topic.kms\_master\_key\_id, an s3-bucket kms\_key\_arn, a CodePipeline encryption\_key, etc. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | The CMK key id. |
<!-- END_TF_DOCS -->
