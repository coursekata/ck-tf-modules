terraform {
  required_version = ">= 1.11.6, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.40"
    }
    # The bucket renders its own name + tags from the context provider the consuming root configures.
    context = {
      source  = "cloudposse/context"
      version = "~> 0.5.0"
    }
  }
}
