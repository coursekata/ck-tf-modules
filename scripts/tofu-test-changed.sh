#!/usr/bin/env bash
# Resolve selected paths to test roots once. Initialize roots serially to warm
# the provider cache, then test independent roots in bounded parallel workers.
set -o pipefail

workers=${TOFU_TEST_JOBS:-2}
if ! [[ "$workers" =~ ^[1-9][0-9]*$ ]]; then
  echo "TOFU_TEST_JOBS must be a positive integer" >&2
  exit 1
fi

resolve_root() {
  local d
  d=$(dirname "$1")
  while :; do
    if compgen -G "$d/tests/*.tftest.hcl" >/dev/null; then
      printf '%s\n' "$d"
      return 0
    fi
    if [ "$d" = "." ] || [ "$d" = "/" ]; then return 0; fi
    d=$(dirname "$d")
  done
}

roots=$(for f in "$@"; do resolve_root "$f"; done | sort -u)
[ -z "$roots" ] && exit 0

logs=$(mktemp -d "${TMPDIR:-/tmp}/tofu-test.XXXXXX") || exit 1
trap 'rm -rf "$logs"' EXIT

rc=0
ready=()
while IFS= read -r d; do
  echo "==> tofu init: $d"
  started=$SECONDS
  # Reconcile modules/providers even when .terraform is present: it can be
  # incomplete or stale after dependency changes. Never initialize a backend.
  if (cd "$d" && tofu init -backend=false -input=false -no-color </dev/null); then
    echo "==> tofu init: $d passed ($((SECONDS - started))s)"
    ready+=("$d")
  else
    echo "==> tofu init: $d FAILED ($((SECONDS - started))s); tests could not run" >&2
    rc=1
  fi
done <<< "$roots"

# Invoked in the bash workers launched by xargs below.
# shellcheck disable=SC2329
run_test() (
  cd "$1" || exit 1
  started=$SECONDS
  echo "==> tofu test: $1"
  tofu test -no-color </dev/null
  result=$?
  echo "==> tofu test: $1 exit=$result ($((SECONDS - started))s)"
  exit "$result"
)

# xargs supplies the worker pool and aggregates failures. Normalize a worker's
# failure to 1 because xargs treats exit 255 as a request to stop scheduling.
# require_serial on the hook keeps the deduplicated roots in one invocation.
export -f run_test
# Expansion belongs to the worker shell, where $1/$2 are its root and log path.
# shellcheck disable=SC2016
worker_command='run_test "$1" >"$2" 2>&1 || exit 1'
if [ "${#ready[@]}" -gt 0 ]; then
  echo "==> tofu test: ${#ready[@]} root(s), up to $workers workers"
  for i in "${!ready[@]}"; do
    printf '%s\0%s\0' "${ready[$i]}" "$logs/$i.log"
  done | xargs -0 -n 2 -P "$workers" bash -c "$worker_command" _ || rc=1

  # Print complete per-root logs after all workers finish, without interleaving.
  for i in "${!ready[@]}"; do
    cat "$logs/$i.log" || rc=1
  done
fi

exit "$rc"
