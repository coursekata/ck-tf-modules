#!/usr/bin/env bash
# Enforce that every modules/*/context.tf is byte-identical. The file is COPIED into each
# label-rendering module (not shared via a module reference), so nothing else stops a copy from
# drifting; a drifted-but-valid copy still passes `terraform validate`, so only a byte-comparison
# catches it. Presence is not checked here: a module that references a context label without a
# context.tf already fails `terraform validate` ("Reference to undeclared resource").

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
ref=""
for f in $(find modules -maxdepth 2 -name context.tf | sort); do
  if [ -z "$ref" ]; then
    ref="$f"
    continue
  fi
  if ! cmp -s "$ref" "$f"; then
    echo "drift: $f differs from $ref — context.tf must be byte-identical across modules"
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "context.tf: byte-identical across modules"
exit "$fail"
