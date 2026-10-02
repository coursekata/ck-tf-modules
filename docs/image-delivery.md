# Image delivery

The shared image lane uses two immutable ECR repositories. Pull requests build and test a candidate, while a protected branch copies that exact digest into the release repository. Deployments consume only release digests.

The reusable pieces are:

- `modules/ecr-repo`: one immutable repository with either candidate-age or release-count retention.
- `modules/ecr-image-ci`: GitHub OIDC roles with candidate/release write separation.
- `.github/actions/git-content-id`: a content tag stable across a pull request's merge commit and the resulting branch commit.
- `.github/actions/ecr-image-state`: an idempotent release/candidate lookup before a build.
- `.github/actions/ecr-promote-image`: tested policy for waiting on and copying an exact candidate digest.
- `.github/workflows/ecr-promote-image.yml`: an exact-digest promotion job using official AWS actions and Docker Buildx.

Application-specific tests stay in the consuming repository. A candidate is pushed only after those checks pass. Consumers pin released shared components by an immutable `vMAJOR.MINOR.PATCH` tag.

Release the shared tag before merging a consumer that references it. Provision the consumer's repositories and OIDC roles, then install its non-secret GitHub configuration variables before enabling the image workflow. A workflow introduced for the first time does not run on its own pull request, so bootstrap it on the default branch before using a follow-up pull request to publish the first candidate.
