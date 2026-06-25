# log-group

A CloudWatch Logs log group primitive — the logging sibling of [`s3-bucket`](../s3-bucket). It renders
its name + tags from the org context provider in the canonical order, prepends an optional
AWS-mandated source prefix (`/aws/lambda/`, `/aws/ecs/`, `/aws/cloudtrail/`), and applies a retention
the caller must choose. Centralizing the naming/tagging/retention convention here keeps every log
group across the org consistent in one place instead of each module hand-rolling its own.

Encryption defaults to AWS-managed — the proportional posture for operational and audit-mirror log
groups, where the durable record's integrity lives in S3 Object Lock, not a log-group CMK. Pass
`kms_key_arn` for a customer key (and grant `logs.<region>.amazonaws.com` in that key's policy on the
caller side).

## Usage

```hcl
# ECS task logs (the /aws/ecs/ prefix AWS mandates) -> /aws/ecs/ck-datalake-stg-dbt-runner
module "runner_logs" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/log-group?ref=v0.5.0"

  name              = "dbt-runner"
  name_prefix       = "/aws/ecs/"
  retention_in_days = 30
}

# The org CloudTrail CloudWatch mirror -> /aws/cloudtrail/ck-org-cloudtrail
module "cloudtrail_logs" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/log-group?ref=v0.5.0"

  name              = "cloudtrail"
  name_prefix       = "/aws/cloudtrail/"
  retention_in_days = 90
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
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [context_label.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_retention_in_days"></a> [retention\_in\_days](#input\_retention\_in\_days) | Log retention. No default — each caller chooses deliberately. Must be a CloudWatch-supported value. | `number` | n/a | yes |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | Optional `attributes` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Optional `environment` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN to encrypt the log group with a customer CMK. null (default) uses AWS-managed encryption. The key's policy must grant logs.<region>.amazonaws.com — set that on the caller side. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | The `name` slot. Defaults to the module's opinionated name; override per group. | `string` | `"log-group"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Optional prefix prepended to the rendered name. Use for the AWS-mandated source prefixes<br/>("/aws/lambda/", "/aws/ecs/") or a convention prefix ("/aws/cloudtrail/"). "" leaves the bare<br/>rendered id. Include the trailing slash. The classification still comes from the slots. | `string` | `""` | no |
| <a name="input_surface"></a> [surface](#input\_surface) | Optional `surface` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the log group (no trailing :*). CloudTrail's cloud\_watch\_logs\_group\_arn wants the arn with a ':*' suffix — append it at the call site. |
| <a name="output_name"></a> [name](#output\_name) | Name of the log group (the prefix + rendered id). |
<!-- END_TF_DOCS -->
