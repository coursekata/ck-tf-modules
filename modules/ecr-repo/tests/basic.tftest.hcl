mock_provider "aws" {}

provider "context" {
  property_order  = ["namespace", "domain", "environment", "surface", "name", "attributes"]
  tags_value_case = "lower"
  properties = {
    namespace   = { required = true, min_length = 1, validation_regex = "^[a-z0-9-]+$" }
    domain      = { validation_regex = "^[a-z0-9-]*$" }
    environment = { validation_regex = "^[a-z0-9-]*$" }
    surface     = { validation_regex = "^[a-z0-9-]*$" }
    name        = { validation_regex = "^[a-z0-9-]*$" }
    attributes  = { validation_regex = "^[a-z0-9-]*$" }
  }
  values = { namespace = "ck", domain = "datalake", environment = "stg" }
}

variables {
  name            = "dbt-runner"
  attributes      = "image"
  retain_n_images = 100
}

run "ecr_posture" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "ECR repo must have image scanning on push enabled"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "ECR repo encryption must be AES256 (the default)"
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "ECR repo tags must be immutable: the deployed digest is resolved from a tag, so a re-pointed tag redeploys different bytes with no source change"
  }

  assert {
    condition     = aws_ecr_repository.this.name == "ck-datalake-stg-dbt-runner-image"
    error_message = "ECR repo name must derive from the context provider plus name=dbt-runner and the caller-supplied `attributes=image` value"
  }
}
