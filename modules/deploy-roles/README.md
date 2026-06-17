# deploy-roles

The reusable **spoke deploy roles** for the org's OIDC hub-spoke delivery model. Creates the
two IAM roles a spoke's CI assumes (via the ck-tooling hub) to plan/apply its own
infrastructure:

- **apply (RW)** — assumable ONLY by the spoke's hub CI *apply* role (itself reachable only
  from the spoke's protected GitHub Environment): the gated write path.
- **plan (RO, optional)** — assumable ONLY by the hub CI *plan* role (PR runs): the read path
  for PR plan previews. Omit `hub_plan_role_arn` for an apply-only spoke.

The standardized, security-critical part is the **trust**: each role trusts EXACTLY one hub
role ARN (no wildcard, no cross-trust between the plan and apply paths) for `sts:AssumeRole` +
`sts:TagSession`. The spoke supplies its own permissions (`*_policy_arns` / `*_inline_policy`).
Names + tags come from the **`cloudposse/context` provider** the consuming root configures —
which must declare the `attributes` property so the plan role can render `<...>-plan`. The
roles are pinned to `expected_account_id` via a precondition, so a wrong-profile apply can't
mint deploy roles in the wrong account.

## Usage (a spoke's `bootstrap/deploy-roles` root)

```hcl
# providers.tf — the org context (this repo's namespace/tenant; declare `attributes`)
provider "context" {
  property_order  = ["namespace", "tenant", "name", "attributes"]
  tags_value_case = "lower"
  properties = {
    namespace  = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    tenant     = { validation_regex = "^[a-z0-9-]*$" }
    name       = { validation_regex = "^[a-z0-9-]*$" }
    attributes = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = { namespace = "ck", tenant = "org" }
}

module "deploy_roles" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/deploy-roles?ref=v0.2.0"

  expected_account_id = "232672477651"

  # The hub CI roles permitted to assume each spoke role (from ck-tooling/environments/hub):
  hub_apply_role_arn = "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-apply"
  hub_plan_role_arn  = "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-plan" # null = apply-only

  # The spoke's own deploy permissions (managed ARNs and/or inline JSON):
  apply_policy_arns = [aws_iam_policy.org_deploy.arn]
  plan_policy_arns  = [aws_iam_policy.org_readonly.arn]
}
```

Wire the outputs back into the hub's `spokes.auto.tfvars` (`apply_role_arns` / `plan_role_arns`)
and into the env-root providers' `assume_role`.

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
| [aws_iam_role.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.apply_inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.plan_inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.apply_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.plan_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.apply_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [context_label.apply](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_label.plan](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.apply](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |
| [context_tags.plan](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_expected_account_id"></a> [expected\_account\_id](#input\_expected\_account\_id) | AWS account these deploy roles must be created in (the spoke account). A precondition fails the plan if the provider resolved elsewhere, so a wrong-profile apply can't mint deploy roles in the wrong account. | `string` | n/a | yes |
| <a name="input_hub_apply_role_arn"></a> [hub\_apply\_role\_arn](#input\_hub\_apply\_role\_arn) | ARN of the hub CI APPLY role (in the tooling account) permitted to sts:AssumeRole the apply (RW) deploy role. This is the gated write path: the hub apply role is itself assumable only from the spoke's protected GitHub Environment. | `string` | n/a | yes |
| <a name="input_apply_inline_policy"></a> [apply\_inline\_policy](#input\_apply\_inline\_policy) | Optional inline IAM policy JSON for the apply (RW) deploy role (e.g. from a data.aws\_iam\_policy\_document). | `string` | `null` | no |
| <a name="input_apply_policy_arns"></a> [apply\_policy\_arns](#input\_apply\_policy\_arns) | Managed IAM policy ARNs attached to the apply (RW) deploy role — the spoke's deploy permissions. Use these or apply\_inline\_policy (at least one is required). | `list(string)` | `[]` | no |
| <a name="input_hub_plan_role_arn"></a> [hub\_plan\_role\_arn](#input\_hub\_plan\_role\_arn) | ARN of the hub CI PLAN role permitted to sts:AssumeRole the plan (RO) deploy role. Leave null for an apply-only spoke (no PR plan role is created). | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | The context `name` slot for the roles. Renders as <namespace>-<tenant>-<name> (apply) and <namespace>-<tenant>-<name>-plan (plan), e.g. ck-org-deploy / ck-org-deploy-plan. | `string` | `"deploy"` | no |
| <a name="input_plan_inline_policy"></a> [plan\_inline\_policy](#input\_plan\_inline\_policy) | Optional inline IAM policy JSON for the plan (RO) deploy role. Only used when hub\_plan\_role\_arn is set. | `string` | `null` | no |
| <a name="input_plan_policy_arns"></a> [plan\_policy\_arns](#input\_plan\_policy\_arns) | Managed IAM policy ARNs attached to the plan (RO) deploy role. Only used when hub\_plan\_role\_arn is set. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apply_role_arn"></a> [apply\_role\_arn](#output\_apply\_role\_arn) | ARN of the apply (RW) deploy role — wire this into the hub's apply\_role\_arns for this spoke. |
| <a name="output_apply_role_name"></a> [apply\_role\_name](#output\_apply\_role\_name) | Name of the apply (RW) deploy role (e.g. ck-org-deploy). |
| <a name="output_plan_role_arn"></a> [plan\_role\_arn](#output\_plan\_role\_arn) | ARN of the plan (RO) deploy role — wire into the hub's plan\_role\_arns. null for an apply-only spoke. |
| <a name="output_plan_role_name"></a> [plan\_role\_name](#output\_plan\_role\_name) | Name of the plan (RO) deploy role (e.g. ck-org-deploy-plan). null for an apply-only spoke. |
<!-- END_TF_DOCS -->
