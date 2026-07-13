# notifications

A **KMS-encrypted SNS topic delivered to Slack via AWS Chatbot** — the org's reusable notification
primitive, generalized from the datalake `etl-alerting` stack (the alarms / EventBridge rules that
*publish* stay with their caller; this owns the topic, its policy, and the Slack binding). Native
Chatbot SNS subscription, no webhook Lambda; the channel is **read-only-guardrailed** so a
Slack-issued AWS CLI can never mutate resources.

Name + tags come from the **`cloudposse/context` provider**. The **`publishers`** seam grants
`sns:Publish` to services or AWS principals; **service** publishers automatically get an
`aws:SourceAccount = (this account)` confused-deputy guard. Pass the encrypting CMK as `kms_key_arn`
(e.g. from the [`kms`](../kms) module) and grant the publishers' services — and
`chatbot.amazonaws.com` to `kms:Decrypt` — on that key.

> The Slack workspace must be **authorized once** in this account's AWS Chatbot console before any
> message delivers; until then the config applies cleanly but stays silent.

## Usage

```hcl
module "cd_notifications" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/notifications?ref=v0.5.2"

  # slots come from the root context provider
  kms_key_arn        = module.cd_kms.key_arn
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id

  publishers = [
    { sid = "AllowCodeStarNotifications", principal_service = "codestar-notifications.amazonaws.com" },
    { sid = "AllowEventBridgeDrift", principal_service = "events.amazonaws.com" },
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
| [aws_chatbot_slack_channel_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/chatbot_slack_channel_configuration) | resource |
| [aws_iam_role.chatbot](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.chatbot_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.chatbot_resource_explorer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_sns_topic.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.chatbot_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [context_label.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_slack_channel_id"></a> [slack\_channel\_id](#input\_slack\_channel\_id) | Slack channel ID for AWS Chatbot delivery — an input, not a '#channel' name. | `string` | n/a | yes |
| <a name="input_slack_workspace_id"></a> [slack\_workspace\_id](#input\_slack\_workspace\_id) | Slack workspace (team) ID for AWS Chatbot delivery — an input, not a baked identifier. The workspace must be authorized once in this account's Chatbot console before messages deliver. | `string` | n/a | yes |
| <a name="input_allow_unencrypted"></a> [allow\_unencrypted](#input\_allow\_unencrypted) | Explicit opt-out acknowledging an UNENCRYPTED topic (kms\_key\_arn = null). Default false — a CMK is the baseline; you cannot get an unencrypted topic by omission, only by deliberately setting this. Exists only for a stack where a KMS grant to the Chatbot service-linked role isn't in place and encryption would drop Slack delivery. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | Optional `attributes` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |
| <a name="input_chatbot_guardrail_policy_arns"></a> [chatbot\_guardrail\_policy\_arns](#input\_chatbot\_guardrail\_policy\_arns) | IAM guardrail policies bounding what Slack-issued AWS actions Chatbot may take. null (default) applies AWS-managed ReadOnlyAccess — a read-only channel that can never mutate resources. | `list(string)` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Optional `environment` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN encrypting the SNS topic (aws\_sns\_topic.kms\_master\_key\_id). The key's policy must let the publishers' services (and chatbot.amazonaws.com to Decrypt) use it — grant that on the key, e.g. via the kms module's grants seam. null leaves the topic UNENCRYPTED and requires allow\_unencrypted = true — for a stack where an encrypted-SNS→Chatbot grant chain (incl. the Chatbot service-linked role) isn't yet in place and would silently drop delivery. | `string` | `null` | no |
| <a name="input_logging_level"></a> [logging\_level](#input\_logging\_level) | AWS Chatbot CloudWatch logging level (ERROR \| INFO \| NONE). Default ERROR. | `string` | `"ERROR"` | no |
| <a name="input_name"></a> [name](#input\_name) | The `name` slot. Defaults to "notifications"; override per topic. Names the SNS topic, the Chatbot config, and the Chatbot role (<rendered-id>-chatbot). | `string` | `"notifications"` | no |
| <a name="input_publishers"></a> [publishers](#input\_publishers) | Principals allowed sns:Publish to the topic, merged into the topic policy alongside the always-on<br/>root-account administration statement. Each becomes one Allow statement. Name EXACTLY ONE<br/>principal per entry: a service (principal\_service, e.g. "cloudwatch.amazonaws.com",<br/>"events.amazonaws.com", "codestar-notifications.amazonaws.com") OR an AWS principal<br/>(principal\_aws, a role/account ARN). SERVICE publishers automatically get an aws:SourceAccount =<br/>(this account) confused-deputy condition; add more conditions if needed. | <pre>list(object({<br/>    sid               = string<br/>    principal_service = optional(string)<br/>    principal_aws     = optional(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_surface"></a> [surface](#input\_surface) | Optional `surface` slot. null/unset inherits the provider base; "" suppresses it here; a value overrides. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_chatbot_role_arn"></a> [chatbot\_role\_arn](#output\_chatbot\_role\_arn) | ARN of the read-only-guardrailed AWS Chatbot channel role. |
| <a name="output_slack_channel_configuration_arn"></a> [slack\_channel\_configuration\_arn](#output\_slack\_channel\_configuration\_arn) | The AWS Chatbot Slack channel configuration ARN. |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | The notification SNS topic ARN. Add a source by targeting this ARN (a CloudWatch alarm action, an EventBridge target, a CodeStar-notifications rule) — one topic, one Chatbot binding. |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | The SNS topic name (the rendered id). |
<!-- END_TF_DOCS -->
