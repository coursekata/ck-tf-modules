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
