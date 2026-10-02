#!/usr/bin/env bash
set -euo pipefail

: "${CANDIDATE_REPOSITORY:?candidate repository is required}"
: "${IMAGE_TAG:?image tag is required}"
: "${POLL_SECONDS:?poll interval is required}"
: "${REGISTRY:?registry is required}"
: "${RELEASE_REPOSITORY:?release repository is required}"
: "${WAIT_SECONDS:?wait duration is required}"
: "${GITHUB_OUTPUT:?GitHub output file is required}"
: "${GITHUB_STEP_SUMMARY:?GitHub step summary file is required}"

if ! [[ "$POLL_SECONDS" =~ ^[1-9][0-9]*$ && "$WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::poll_seconds and wait_seconds must be positive whole numbers."
  exit 1
fi

digest() {
  local error
  if error=$(aws ecr describe-images --no-cli-pager --repository-name "$1" \
    --image-ids imageTag="$2" --query 'imageDetails[0].imageDigest' --output text 2>&1); then
    printf '%s\n' "$error"
    return 0
  fi
  case "$error" in
    *ImageNotFoundException*) return 1 ;;
    *) echo "::error::$error" >&2; return 2 ;;
  esac
}

if released=$(digest "$RELEASE_REPOSITORY" "$IMAGE_TAG"); then
  echo "digest=$released" >> "$GITHUB_OUTPUT"
  echo "$RELEASE_REPOSITORY:$IMAGE_TAG is already released as $released." >> "$GITHUB_STEP_SUMMARY"
  exit 0
else
  result=$?
  [ "$result" -eq 1 ] || exit "$result"
fi

candidate=""
attempts=$(((WAIT_SECONDS + POLL_SECONDS - 1) / POLL_SECONDS))
for ((attempt = 1; attempt <= attempts; attempt++)); do
  if candidate=$(digest "$CANDIDATE_REPOSITORY" "$IMAGE_TAG"); then
    break
  else
    result=$?
    [ "$result" -eq 1 ] || exit "$result"
  fi

  if [ "$attempt" -eq "$attempts" ]; then
    echo "::error::No tested candidate arrived for $IMAGE_TAG within $WAIT_SECONDS seconds."
    exit 1
  fi
  sleep "$POLL_SECONDS"
done

docker buildx imagetools create \
  --prefer-index=false \
  --tag "$REGISTRY/$RELEASE_REPOSITORY:$IMAGE_TAG" \
  "$REGISTRY/$CANDIDATE_REPOSITORY@$candidate"

if landed=$(digest "$RELEASE_REPOSITORY" "$IMAGE_TAG"); then
  :
else
  result=$?
  if [ "$result" -eq 1 ]; then
    echo "::error::The promoted tag is not visible in the release repository."
  fi
  exit "$result"
fi

if [ "$landed" != "$candidate" ]; then
  echo "::error::Promotion landed $landed; the tested candidate is $candidate."
  exit 1
fi

echo "digest=$landed" >> "$GITHUB_OUTPUT"
echo "Promoted $landed as $RELEASE_REPOSITORY:$IMAGE_TAG." >> "$GITHUB_STEP_SUMMARY"
