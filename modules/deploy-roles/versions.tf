terraform {
  required_version = ">= 1.11.6, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    # Names + tags come from the cloudposse/context provider (the consuming root configures it).
    # Pinned to 0.5 patch range — pre-1.0, so ride 0.5.x fixes but never auto-jump to 0.6.
    context = {
      source  = "cloudposse/context"
      version = "~> 0.5.0"
    }
  }
}
