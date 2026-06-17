terraform {
  required_version = ">= 1.11.6, < 2.0"
  # No required_providers: this module emits constants only — it declares no resources and
  # uses no provider. Its outputs configure the cloudposse/context provider in each consuming root.
}
