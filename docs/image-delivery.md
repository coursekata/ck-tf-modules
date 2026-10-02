# Image delivery

Pull requests build and test images without AWS access. After review, the protected branch rebuilds the same source, repeats the runtime check, and publishes directly to an immutable release repository. Deployments resolve a release tag to its digest.

The reusable pieces are:

- `modules/ecr-repo`: an immutable repository with release-count retention.
- `modules/ecr-image-publisher`: a GitHub OIDC role trusted only from the configured protected branch and scoped to one repository.
- `.github/actions/git-content-id`: a content tag derived from the files that define the image.

Application-specific build and runtime checks stay in the consuming repository. The publishing credentials are configured only after those checks pass. Consumers pin shared components by an immutable `vMAJOR.MINOR.PATCH` tag.

Release the shared tag before merging a consumer that references it. Provision the consumer's repository and OIDC role, then install its non-secret GitHub configuration variables before enabling publishing.
