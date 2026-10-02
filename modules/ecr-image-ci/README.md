# ecr-image-ci

GitHub Actions identities for a two-repository image delivery lane.

Pull requests may inspect releases and write only to the candidate repository. The configured branch may read candidates and write only to the release repository. This keeps unreviewed image bytes out of the repository that deployments consume and prevents the promotion identity from manufacturing its own candidate.

The account-level GitHub OIDC provider remains owned by the consuming environment. Pass its ARN with the candidate and release repository ARNs:

```hcl
module "image_ci" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/ecr-image-ci?ref=vX.Y.Z"

  name                         = "frontend"
  stage_attributes             = "image-stage"
  publish_attributes           = "image-publish"
  github_oidc_provider_arn     = data.aws_iam_openid_connect_provider.github.arn
  github_repository            = "coursekata/app"
  publish_ref                  = "refs/heads/develop"
  candidate_repository_arn     = module.candidate_image.repository_arn
  release_repository_arn       = module.release_image.repository_arn
}
```

Live IAM simulations fail the plan or apply unless both roles can authenticate, complete every repository operation their workflows require, and cannot mutate the wrong repository. Incomplete simulator responses also fail. Disable the simulations only in mocked consumer tests before real roles exist.
