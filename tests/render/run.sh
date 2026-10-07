#!/usr/bin/env bash
# Renders templates/configmap.yaml for every case in tests/render/cases/ and
# checks the result. Usage: tests/render/run.sh [case-name-filter]
#
# A case dir holds values.yaml plus either:
#   expect.jq    a jq program run against config.json; must print true
#   expect-fail  a regex the `helm template` stderr must match (render must fail)
# With EDGE_SRC set to an Edge checkout, every rendered config.json must also be
# accepted by the Edge's own config loader (see edgecheck/).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart="$(cd "$here/../.." && pwd)"
filter="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

edgecheck=""
if [[ -n "${EDGE_SRC:-}" ]]; then
  cat > "$tmp/overlay.json" <<JSON
{"Replace": {"${EDGE_SRC}/cmd/edgecheck/main.go": "${here}/edgecheck/main.go"}}
JSON
  edgecheck="$tmp/edgecheck"
  (cd "$EDGE_SRC" && go build -overlay "$tmp/overlay.json" -o "$edgecheck" ./cmd/edgecheck)
fi

pass=0
fail=0
report() { # status name detail
  if [[ "$1" == PASS ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
  echo "$1 $2${3:+: $3}"
}

for dir in "$here"/cases/*/; do
  name="$(basename "$dir")"
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue

  if [[ -f "$dir/expect-fail" ]]; then
    if out="$(helm template t "$chart" -f "$dir/values.yaml" -s templates/configmap.yaml 2>&1)"; then
      report FAIL "$name" "render succeeded, expected failure"
    elif grep -Eq "$(cat "$dir/expect-fail")" <<<"$out"; then
      report PASS "$name"
    else
      report FAIL "$name" "error did not match $(cat "$dir/expect-fail"): $out"
    fi
    continue
  fi

  if ! out="$(helm template t "$chart" -f "$dir/values.yaml" -s templates/configmap.yaml 2>&1)"; then
    report FAIL "$name" "render failed: $out"
    continue
  fi
  cfg="$tmp/$name.json"
  yq -r '.data["config.json"]' <<<"$out" > "$cfg"
  if ! jq -e . "$cfg" >/dev/null 2>"$tmp/err"; then
    report FAIL "$name" "config.json is not valid JSON: $(cat "$tmp/err")"
    continue
  fi
  if [[ "$(jq -f "$dir/expect.jq" "$cfg" 2>&1)" != true ]]; then
    report FAIL "$name" "expect.jq: $(jq -f "$dir/expect.jq" "$cfg" 2>&1 | head -5 | tr '\n' ' ')"
    continue
  fi
  if [[ -n "$edgecheck" ]] && ! err="$("$edgecheck" < "$cfg" 2>&1)"; then
    report FAIL "$name" "Edge rejected config: $err"
    continue
  fi
  report PASS "$name"
done

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
