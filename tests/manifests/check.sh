#!/usr/bin/env bash
# Checks the standalone manifests.yaml: the embedded config.json is valid and
# watches the informers the chart does, the ClusterRole can read endpoints, and
# the image tag matches the chart appVersion. Needs yq and jq.
# Usage: tests/manifests/check.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
file="$root/manifests.yaml"
fail=0
check() { # description, command...
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then echo "ok: $desc"; else echo "FAIL: $desc" >&2; fail=1; fi
}

cfg="$(yq 'select(.kind == "ConfigMap") | .data["config.json"]' "$file")"
check "config.json is valid JSON" jq -e . <<<"$cfg"
check "kube.resources has endpoints" jq -e '.kube.resources | index("endpoints")' <<<"$cfg"
check "kube.resources has k8services" jq -e '.kube.resources | index("k8services")' <<<"$cfg"
check "kube.resources has no services" jq -e '.kube.resources | index("services") | not' <<<"$cfg"

role="$(yq -o=json 'select(.kind == "ClusterRole")' "$file")"
check "ClusterRole core rule has endpoints" \
  jq -e '.rules[] | select(.apiGroups == [""]) | .resources | index("endpoints")' <<<"$role"

app_version="$(yq -r .appVersion "$root/Chart.yaml")"
images="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[].image' "$file")"
check "nofireai/edge image tag is appVersion $app_version" grep -Fxq "nofireai/edge:$app_version" <<<"$images"

exit "$fail"
