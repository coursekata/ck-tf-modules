# Root-level account guard for the OIDC hub-spoke model. Every root calls this once per provider,
# as its preamble: a wrong-credential plan then fails BEFORE any resource is created, instead of
# landing it in the wrong account. The assertion lives here — at the root, where the credential is
# established — not inside each resource module, so it is uniform across every root and independent
# of which resources a root happens to create (a root that builds resources inline, with no guarded
# module, is still protected).
#
# A root that targets more than one account (e.g. a multi-spoke bootstrap with aliased providers)
# calls the module once per account, passing the matching provider:
#
#   module "guard_security" {
#     source              = ".../account-guard"
#     expected_account_id = var.security_account_id
#   }
#   module "guard_archive" {
#     source              = ".../account-guard"
#     providers           = { aws = aws.log_archive }
#     expected_account_id = var.log_archive_account_id
#   }
data "aws_caller_identity" "current" {}

# terraform_data creates nothing in AWS; it exists only to host the plan-time precondition that
# fails the plan when the provider resolved to an account other than expected_account_id.
resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
      error_message = "Provider resolved to account ${data.aws_caller_identity.current.account_id}; expected ${var.expected_account_id}. Refusing to plan against the wrong account."
    }
  }
}
