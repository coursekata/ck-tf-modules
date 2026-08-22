# log-group

A CloudWatch Logs log group primitive. It renders its name + tags from the **`cloudposse/context`
provider** (the consuming root configures it) in the canonical order, prepends an optional
AWS-mandated source prefix (`/aws/lambda/`, `/aws/ecs/`, `/aws/cloudtrail/`), and applies a retention
the caller must choose. Centralizing the naming/tagging/retention convention here keeps every log
group across the org consistent in one place instead of each module hand-rolling its own.

Encryption defaults to AWS-managed — the proportional posture for operational and audit-mirror log
groups, where the durable record's integrity lives in S3 Object Lock, not a log-group CMK. Pass
`kms_key_arn` for a customer key (and grant `logs.<region>.amazonaws.com` in that key's policy on the
caller side).

## Usage

```hcl
# ECS task logs (the /aws/ecs/ prefix AWS mandates) -> /aws/ecs/ck-datalake-stg-dbt-runner
module "runner_logs" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/log-group?ref=v0.5.0"

  name              = "dbt-runner"
  name_prefix       = "/aws/ecs/"
  retention_in_days = 30
}

# The org CloudTrail CloudWatch mirror -> /aws/cloudtrail/ck-org-cloudtrail
module "cloudtrail_logs" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/log-group?ref=v0.5.0"

  name              = "cloudtrail"
  name_prefix       = "/aws/cloudtrail/"
  retention_in_days = 90
}
```
