# ecr-image-pipeline

The ECR side of the image pipeline for one GitHub repository: a candidate, a release and a cache repository for each image it builds, three roles, and a release-read role for each repository that deploys the images.

- The **candidate role** trusts any job on the default branch outside an environment, which is how a push and a run by hand both reach it. It pushes candidate images and caches and reads the release cache.
- The **cache-read role** trusts the repository's `pull_request` jobs. It reads the release cache and nothing else.
- The **release role** trusts only jobs in the repository's `release` environment. It reads candidates and writes the release and cache repositories.
- A **release-read role** per repository in `release_readers`, which maps each consumer repository to its own default branch, trusts that branch and nothing else. It describes and pulls the release repositories and nothing else, which is what a consumer's Renovate needs to move an image pin. A repository that deploys its own images names itself; the frontend's module names ck-app-tf with its `main`, though the frontend itself releases from `develop`. The role's name drops the ids of GitHub's immutable subject form and renders the rest in lowercase with hyphens, so a repository keeps its role when it moves to that form, and the plan refuses a name longer than IAM's 64 characters or one two readers share.

Candidate and release tags are immutable. The cache repository's tags are mutable, because each release moves the cache tag to its own cache, and only the release role writes it. Candidates expire 30 days after push, tagged or not. A cache that a later release replaced keeps no tag and expires 7 days after its push; the tagged cache never expires, and neither do released images. No role can delete an image, change a lifecycle policy or loosen a repository, by an explicit deny.

The `release` environment must exist, with a deployment branch policy naming only the default branch, before the release role is trusted: GitHub creates a missing environment, with no rules, for any workflow that names it. The account's GitHub OIDC provider stays with the consuming account's identity root.

```hcl
module "image_pipeline" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/ecr-image-pipeline?ref=vX.Y.Z"

  images                   = ["dbt-runner"]
  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  github_repository        = "coursekata/ck-datalake"
  default_branch           = "main"
  release_readers          = { "coursekata/ck-datalake" = "main" }
}
```

`github_repository` is the repository as GitHub writes it in the OIDC subject. A repository created after 2026-07-15, or renamed or transferred since, uses the immutable form `owner@<owner id>/repository@<repository id>`.
