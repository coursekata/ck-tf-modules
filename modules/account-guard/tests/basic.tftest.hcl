# Unit tests for the account-guard module. mock_provider supplies a fixed aws_caller_identity so
# both paths are deterministic: the guard must PASS when the resolved account matches
# expected_account_id and FAIL the plan when it does not. This is the guard's failure-path test —
# it used to be duplicated as a "wrong_account_is_rejected" run in every resource module's suite;
# now it lives here once.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "232672477651"
    }
  }
}

run "passes_and_outputs_the_verified_account_when_it_matches" {
  command = plan

  variables {
    expected_account_id = "232672477651"
  }

  assert {
    condition     = output.account_id == "232672477651"
    error_message = "the guard must output the verified account id when the provider matches"
  }
}

run "fails_the_plan_when_the_account_differs" {
  command = plan

  variables {
    expected_account_id = "999999999999"
  }

  expect_failures = [
    terraform_data.guard,
  ]
}
