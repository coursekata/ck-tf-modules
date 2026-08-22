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
