# account-guard

A tiny **root preamble** module: it asserts the credential the root is running with resolves to
the account the root is *supposed* to manage, and **fails the plan** otherwise — so a
wrong-profile/-role apply can never create resources in the wrong account.

The assertion belongs at the **root**, where the credential is established — not inside each
resource module. Calling it once in every root makes the guard uniform and independent of which
resources a root creates (a root that builds resources inline, with no guarded module, is still
protected). It is the credential-side sibling of [`context-schema`](../context-schema) (the
labeling-side preamble): every root calls both.

## Usage

```hcl
# one account (the common case)
module "account_guard" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/account-guard?ref=v0.5.0"

  expected_account_id = "123456789012"
}
```

A root that targets **more than one account** (e.g. a multi-spoke bootstrap with aliased
providers) calls the module **once per account**, passing the matching provider:

```hcl
module "guard_security" {
  source              = "git::https://github.com/coursekata/ck-tf-modules.git//modules/account-guard?ref=v0.5.0"
  expected_account_id = var.security_account_id
}

module "guard_archive" {
  source              = "git::https://github.com/coursekata/ck-tf-modules.git//modules/account-guard?ref=v0.5.0"
  providers           = { aws = aws.log_archive }
  expected_account_id = var.log_archive_account_id
}
```

The guard fails at **plan** (a precondition on a no-op `terraform_data`), so nothing is created
when the account is wrong. Reference `module.account_guard.account_id` from a resource to force an
explicit dependency on the check.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.6, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.guard](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_expected_account_id"></a> [expected\_account\_id](#input\_expected\_account\_id) | AWS account this root must run against. The guard fails the plan if the provider resolved to a different account, so a wrong-profile/-role apply can never create resources in the wrong account. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | The verified AWS account ID (equals expected\_account\_id once the guard passes). Reference it from a resource to force an explicit dependency on the check. |
<!-- END_TF_DOCS -->
