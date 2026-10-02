# ecr-image-publisher

Creates the GitHub Actions role that publishes images from one protected branch to one ECR repository. Pull-request jobs receive no AWS role; the protected branch rebuilds the reviewed source before publishing it.

The account-level GitHub OIDC provider remains owned by the consuming account's identity root.

```hcl
module "image_publisher" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/ecr-image-publisher?ref=vX.Y.Z"

  name                     = "frontend"
  attributes               = "image-publish"
  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  github_repository        = "UCLATALL/coursekata"
  publish_ref              = "refs/heads/develop"
  repository_arn           = module.image.repository_arn
}
```
