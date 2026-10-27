# ecr-image-pipeline

The ECR side of the image pipeline for one GitHub repository, for the image workflow in [ck-ci](https://github.com/coursekata/ck-ci/blob/main/image/README.md): a candidate, a release and a cache repository for each image it builds, three roles, and a release-read role for each repository that deploys the images.

- The **candidate role** trusts any job on the default branch outside an environment, which is how a push and a run by hand both reach it. It pushes candidate images and caches and reads the release cache.
- The **cache-read role** trusts the repository's `pull_request` jobs. It reads the release cache and nothing else.
- The **release role** trusts only jobs in the repository's `release` environment. It reads candidates and writes the release and cache repositories.
- A **release-read role** per consumer in `release_readers`, keyed by a label such as the app surface `web`, which names the role, as in `ck-app-stg-api-image-release-read-web`. Each consumer names its repository and the branch its Renovate runs on, and the role trusts that branch and nothing else. It describes and pulls the release repositories and nothing else, which is what a consumer's Renovate needs to move an image pin. A repository that deploys its own images names itself; the api's module names ck-app-web with its `main`, though the api itself releases from `develop`.

Candidate and release tags are immutable, apart from `latest` in a release repository, which each release moves for development pulls; nothing that deploys or pins names it. The cache repository's tags are mutable, because each release moves the cache tag to its own cache, and only the release role writes it. Candidates expire 30 days after push, tagged or not. A cache that a later release replaced keeps no tag and expires 7 days after its push; the tagged cache never expires, and neither do released images. No role can delete an image, change a lifecycle policy or loosen a repository, by an explicit deny.

A repository is named from the root's context, the image's name and the area, as in `ck-app-stg-web-server-release`. Where `image_qualifier_in_names` is left true, `image-` comes before the area, as in `ck-datalake-prd-dbt-runner-image-release`; the lake keeps that form, because an ECR repository cannot be renamed. A new instance sets it false.

`sibling_release_repository_arns` names release repositories of another producer in the same account whose images this producer's builds consume as a build context, as the web server's build copies the api contract out of the api's release. The candidate and cache-read roles may describe and pull them, so a pull request's build and a default-branch build both can. No role may write them, and the release role and the readers get nothing from them. The input belongs on the consuming producer's instance: the web producer's names the api's contract release, as in `arn:aws:ecr:us-west-1:836515410163:repository/ck-app-stg-api-contract-release`, and the api producer's sets nothing.

The `release` environment must exist, with a deployment branch policy naming only the default branch, before the release role is trusted: GitHub creates a missing environment, with no rules, for any workflow that names it. The account's GitHub OIDC provider stays with the consuming account's identity root.

```hcl
module "image_pipeline" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/ecr-image-pipeline?ref=vX.Y.Z"

  images                   = ["server", "contract"]
  image_qualifier_in_names = false
  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  github_repository        = "UCLATALL/coursekata"
  default_branch           = "develop"
  release_readers          = { web = { repository = "coursekata/ck-app-web", branch = "main" } }
}
```

The lake's instance leaves `image_qualifier_in_names` at its default, which keeps its `ck-datalake-prd-dbt-runner-image-*` names.

`github_repository` is the repository as GitHub writes it in the OIDC subject. A repository created after 2026-07-15, or renamed or transferred since, uses the immutable form `owner@<owner id>/repository@<repository id>`.
