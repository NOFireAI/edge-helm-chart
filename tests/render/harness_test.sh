#!/usr/bin/env bash
# Tests for run.sh itself. A symlink inside the chart makes `helm template`
# print a warning on stderr while still succeeding; run.sh must not feed that
# warning to yq as part of the rendered YAML.
set -euo pipefail

chart_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

(cd "$chart_root" && tar --exclude=.git --exclude=node_modules -cf - .) | (mkdir "$tmp/chart" && cd "$tmp/chart" && tar -xf -)
ln -s ../values.yaml "$tmp/chart/templates/stderr-warning-link"

if ! out="$("$tmp/chart/tests/render/run.sh" defaults 2>&1)"; then
  echo "FAIL: run.sh did not pass a case when helm warned on stderr"
  echo "$out"
  exit 1
fi
grep -q '^PASS defaults' <<<"$out" || { echo "FAIL: unexpected output: $out"; exit 1; }
echo "PASS harness: stderr warnings do not leak into the rendered config"
