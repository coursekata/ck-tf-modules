#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ACTION_DIR=$(cd "$TEST_DIR/.." && pwd)

run_case() {
  local scenario=$1
  local expected_status=$2
  local state
  state=$(mktemp -d)

  set +e
  PATH="$TEST_DIR/bin:$PATH" \
    TEST_SCENARIO="$scenario" \
    TEST_STATE="$state" \
    CANDIDATE_REPOSITORY=candidate \
    IMAGE_TAG=content-id \
    POLL_SECONDS=1 \
    REGISTRY=registry \
    RELEASE_REPOSITORY=release \
    WAIT_SECONDS=2 \
    GITHUB_OUTPUT="$state/output" \
    GITHUB_STEP_SUMMARY="$state/summary" \
    "$ACTION_DIR/promote.sh" > "$state/stdout" 2> "$state/stderr"
  local actual_status=$?
  set -e

  if [ "$actual_status" -ne "$expected_status" ]; then
    cat "$state/stdout" "$state/stderr" >&2
    echo "$scenario returned $actual_status; expected $expected_status" >&2
    exit 1
  fi

  case "$scenario" in
    released)
      grep -qx 'digest=sha256:released' "$state/output"
      [ ! -e "$state/promoted" ]
      ;;
    success)
      grep -qx 'digest=sha256:candidate' "$state/output"
      grep -qx '2' "$state/candidate-attempts"
      grep -qx '1' "$state/sleeps"
      test -f "$state/promoted"
      ;;
    aws-error)
      grep -q 'AccessDeniedException' "$state/stderr"
      [ ! -e "$state/promoted" ]
      ;;
    timeout)
      grep -q 'No tested candidate arrived' "$state/stdout"
      [ ! -e "$state/promoted" ]
      ;;
    mismatch)
      grep -q 'Promotion landed sha256:different' "$state/stdout"
      test -f "$state/promoted"
      ;;
  esac
}

run_case released 0
run_case success 0
run_case aws-error 2
run_case timeout 1
run_case mismatch 1

echo "promotion behavior tests passed"
