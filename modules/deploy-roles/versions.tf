terraform {
  required_version = ">= 1.11.6, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    context = {
      source  = "cloudposse/context"
      version = "~> 0.5.0"
    }
  }
}
