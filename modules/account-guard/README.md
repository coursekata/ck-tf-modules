# account-guard

A tiny **root preamble** module: it asserts the credential the root is running with resolves to
the account the root is *supposed* to manage, and **fails the plan** otherwise — so a
wrong-profile/-role apply can never create resources in the wrong account.

The assertion belongs at the **root**, where the credential is established — not inside each
resource module. Calling it once in every root makes the guard uniform and independent of which
resources a root creates (a root that builds resources inline, with no guarded module, is still
protected).

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
