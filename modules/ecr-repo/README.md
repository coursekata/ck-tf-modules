# ecr-repo

ECR repository and lifecycle policy for an immutable container-image store.

OpenTofu owns the repository; the image CI lane owns the bytes. Consumers resolve an immutable content tag to a digest and deploy that digest.

Instantiate it once per stage of the same component, using the context `attributes` slot to distinguish them—for example `image` for releases and `image-candidate` or `image-staging` for build candidates. Two repositories give candidates and releases independent permissions and retention policies.

Pick the retention rule to match: `retain_n_images` for a release repository, where the count is a rollback depth, and `expire_after_days` for a candidate repository, where age is the better measure and a count would let one busy week evict something still in review. Exactly one of the two is required — ECR requires a rule matching `any` to sort last, so a repository cannot carry both.

```hcl
module "release_image" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/ecr-repo?ref=vX.Y.Z"

  name            = "frontend"
  attributes      = "image"
  retain_n_images = 100
}

module "candidate_image" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/ecr-repo?ref=vX.Y.Z"

  name              = "frontend"
  attributes        = "image-candidate"
  expire_after_days = 30
}
```
