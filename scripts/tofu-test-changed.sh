#!/usr/bin/env bash
# Pre-commit gate: run `tofu test` for every module / environment whose tests/
# suite a staged change could invalidate.
#
# Resolves each staged *.tf / *.tftest.hcl path to the nearest ancestor that
# owns a tests/*.tftest.hcl suite, deduplicates, and tests.

resolve_root() {
  local d
  d=$(dirname "$1")
  while [ "$d" != "." ] && [ "$d" != "/" ]; do
    if ls "$d"/tests/*.tftest.hcl >/dev/null 2>&1; then
      printf '%s\n' "$d"
      return 0
    fi
    d=$(dirname "$d")
  done
}

roots=$(for f in "$@"; do resolve_root "$f"; done | sort -u)
[ -z "$roots" ] && exit 0

rc=0
while IFS= read -r d; do
  [ -z "$d" ] && continue
  echo "==> tofu test: $d"
  if ! (
    cd "$d" || exit 1
    if [ ! -d .terraform ]; then
      tofu init -backend=false -input=false -no-color >/dev/null 2>&1 || {
        echo "    skipped — '$d' not initialized; run 'tofu init' there once"
        exit 0
      }
    fi
    tofu test -no-color
  ); then
    rc=1
  fi
done <<< "$roots"

exit $rc
