# Proves the v0.4.0 slot-drop fix: when the consuming root populates `environment` and `surface`
# (the ck-datalake tier-bucket case), the bucket renders the full canonical id
# ck-<domain>-<environment>-<surface>-<name>[-<attributes>] — they are NOT dropped. Pre-v0.4.0
# the module's property list omitted these slots, so a multi-env consumer silently lost them.
# Single-env coverage (slots empty -> rendered away) lives in basic.tftest.hcl.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# A ck-datalake-style root: domain=datalake, environment=stg (source-env-class), surface=raw (tier).
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
  values = { namespace = "ck", domain = "datalake", environment = "stg", surface = "raw" }
}

run "environment_and_surface_render_into_the_id" {
  command = plan

  variables {
    name = "app" # the source system; raw tier of the app pipeline
  }

  # The whole point of v0.4.0: the env + tier are in the name, in canonical order.
  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-raw-app"
    error_message = "bucket must render ck-datalake-stg-raw-app (environment + surface must NOT be dropped)"
  }
  # And they surface as their own tags.
  assert {
    condition = (
      aws_s3_bucket.this.tags["Domain"] == "datalake" &&
      aws_s3_bucket.this.tags["Environment"] == "stg" &&
      aws_s3_bucket.this.tags["Surface"] == "raw"
    )
    error_message = "Domain/Environment/Surface tags must carry the populated slot values"
  }
}

run "attributes_still_trail_the_full_id" {
  command = plan

  variables {
    name       = "app"
    attributes = "writer"
  }

  # attributes remain LAST in the canonical order, after the env/surface/name segment.
  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-raw-app-writer"
    error_message = "attributes must trail the full id: ck-datalake-stg-raw-app-writer"
  }
}
