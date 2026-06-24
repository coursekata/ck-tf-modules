# The ck-datalake tier case: the root provider sets environment + surface as base values, and a
# bucket reconciles them per the context contract —
#   unset/null -> inherit the base   |   a value -> override   |   "" -> suppress the base here.
# Single-env coverage (no base env/surface) lives in basic.tftest.hcl.

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

# Unset slots (null) inherit the base — the bucket renders the full canonical id.
run "unset_slots_inherit_the_base" {
  command = plan

  variables {
    name = "app" # the source system; raw tier of the app pipeline
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-raw-app"
    error_message = "unset environment/surface must inherit the base -> ck-datalake-stg-raw-app"
  }
  assert {
    condition = (
      aws_s3_bucket.this.tags["Domain"] == "datalake" &&
      aws_s3_bucket.this.tags["Environment"] == "stg" &&
      aws_s3_bucket.this.tags["Surface"] == "raw"
    )
    error_message = "Domain/Environment/Surface tags must carry the inherited base values"
  }
}

run "attributes_trail_the_full_id" {
  command = plan

  variables {
    name       = "app"
    attributes = "writer"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-raw-app-writer"
    error_message = "attributes must trail the full id: ck-datalake-stg-raw-app-writer"
  }
}

# Passing "" suppresses a base slot for this bucket (environment drops; surface still inherits).
run "explicit_empty_suppresses_a_base_slot" {
  command = plan

  variables {
    name        = "app"
    environment = ""
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-raw-app"
    error_message = "environment=\"\" must suppress the base stg -> ck-datalake-raw-app"
  }
  assert {
    condition     = !contains(keys(aws_s3_bucket.this.tags), "Environment") && aws_s3_bucket.this.tags["Surface"] == "raw"
    error_message = "suppressed environment must drop its tag while surface still inherits"
  }
}

# Passing null is identical to omitting — it inherits, and never reaches the provider (no crash).
run "explicit_null_inherits_like_omitting" {
  command = plan

  variables {
    name        = "app"
    environment = null
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ck-datalake-stg-raw-app"
    error_message = "environment=null must inherit the base, same as omitting it"
  }
}
