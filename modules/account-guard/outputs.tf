output "account_id" {
  description = "The verified AWS account ID (equals expected_account_id once the guard passes). Reference it from a resource to force an explicit dependency on the check."
  value       = data.aws_caller_identity.current.account_id

  # Don't hand out the account id until the guard precondition has actually passed.
  depends_on = [terraform_data.guard]
}
