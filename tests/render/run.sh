#!/usr/bin/env bash
# Renders templates/configmap.yaml for every case in tests/render/cases/ and
# checks the result. Usage: tests/render/run.sh [case-name-filter]
#
# A case dir holds values.yaml plus either:
#   expect.jq    a jq program run against config.json; must print true
#   expect-fail  a regex the `helm template` stderr must match (render must fail)
# A case with a `replace-values` file renders with values.yaml INSTEAD of the
# chart defaults, like `helm upgrade --reuse-values` from an older release.
# With EDGE_SRC set to an Edge checkout, every rendered config.json must also be
# accepted by the Edge's own config loader (see edgecheck/).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart_root="$(cd "$here/../.." && pwd)"
filter="${1:-}"
[[ -n "${EDGE_SRC:-}" ]] && EDGE_SRC="$(cd "$EDGE_SRC" && pwd)"
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

  chart="$chart_root"
  vals=(-f "$dir/values.yaml")
  if [[ -f "$dir/replace-values" ]]; then
    chart="$tmp/chart-$name"
    mkdir "$chart"
    (cd "$chart_root" && tar --exclude=.git --exclude=node_modules --exclude=tests -cf - .) | (cd "$chart" && tar -xf -)
    cp "$dir/values.yaml" "$chart/values.yaml"
    vals=()
  fi

  # stdout is the manifest; stderr (helm warnings, errors) is kept apart so
  # warnings on a successful render never end up in the YAML handed to yq.
  rc=0
  helm template t "$chart" ${vals[@]+"${vals[@]}"} -s templates/configmap.yaml >"$tmp/out" 2>"$tmp/stderr" || rc=$?

  if [[ -f "$dir/expect-fail" ]]; then
    if [[ "$rc" -eq 0 ]]; then
      report FAIL "$name" "render succeeded, expected failure"
    elif grep -Eq "$(cat "$dir/expect-fail")" "$tmp/stderr"; then
      report PASS "$name"
    else
      report FAIL "$name" "error did not match $(cat "$dir/expect-fail"): $(cat "$tmp/stderr")"
    fi
    continue
  fi

  if [[ "$rc" -ne 0 ]]; then
    report FAIL "$name" "render failed: $(cat "$tmp/stderr")"
    continue
  fi
  out="$(cat "$tmp/out")"
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
