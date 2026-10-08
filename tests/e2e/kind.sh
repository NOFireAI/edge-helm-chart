#!/usr/bin/env bash
# End-to-end check on a throwaway kind cluster: the installed ConfigMap carries
# the namespace scoping keys, the Edge accepts the config and rolls out, a
# values change rolls the pod, and an invalid filter is rejected at render.
# Needs docker, kind, kubectl, helm, jq, yq. Usage: tests/e2e/kind.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cluster=edge-chart-e2e
release=e2e
export KUBECONFIG
KUBECONFIG="$(mktemp)"

cleanup() {
  kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
  rm -f "$KUBECONFIG"
}
trap cleanup EXIT

step() { echo "==> $*"; }
die() { echo "FAIL: $*" >&2; exit 1; }

repo="$(yq -r .image.repository "$root/values.yaml")"
tag="$(yq -r .image.tag "$root/values.yaml")"
image="$repo:$tag"

step "pull $image"
docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"

step "create kind cluster $cluster"
kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
kind create cluster --name "$cluster" --kubeconfig "$KUBECONFIG" --wait 120s
# `kind load docker-image` fails on multi-platform images in Docker's containerd
# store (missing content digest); save only the node's platform instead.
case "$(uname -m)" in arm64|aarch64) platform=linux/arm64 ;; *) platform=linux/amd64 ;; esac
archive="$(mktemp)"
docker save --platform "$platform" "$image" -o "$archive" 2>/dev/null || docker save "$image" -o "$archive"
kind load image-archive "$archive" --name "$cluster"
rm -f "$archive"

cm_config() {
  local cm
  cm="$(kubectl get cm -l "app.kubernetes.io/instance=$release" -o name | grep -- '-config$')"
  kubectl get "$cm" -o jsonpath='{.data.config\.json}'
}
selector="app.kubernetes.io/instance=$release,app.kubernetes.io/name=nofire-edge"
checksum() {
  kubectl get deploy -l "$selector" \
    -o jsonpath='{.items[0].spec.template.metadata.annotations.checksum/config}'
}
# Name of the live pod whose checksum/config annotation equals $1.
pod_with_checksum() {
  kubectl get pods -l "$selector" -o json | jq -r --arg c "$1" \
    '.items[] | select(.metadata.deletionTimestamp == null and .metadata.annotations["checksum/config"] == $c) | .metadata.name' | head -1
}
assert() { # description, config.json, jq expression
  jq -e "$3" <<<"$2" >/dev/null || die "$1: jq '$3' failed on: $2"
  echo "ok: $1"
}

step "helm install (namespaceFilter allow [default])"
helm install "$release" "$root" -f "$root/ci/kind-values.yaml" --wait=false
cfg="$(cm_config)"
assert "installed ConfigMap has allow filter" "$cfg" \
  '.kube.namespaceFilter == {"mode":"allow","namespaces":["default"]}'
assert "installed ConfigMap has netobs keys" "$cfg" \
  '.netobs.edgeExistenceTtl == "1h" and .netobs.excludeNamespaces == ["x"]'
before="$(checksum)"

step "rollout (the Edge accepted the config)"
kubectl rollout status deploy -l "$selector" --timeout=180s \
  || { kubectl logs -l "$selector" --tail=50 || true; die "rollout failed"; }
# The Edge logs its loaded config at startup (cmd/edge/main.go); there is no
# dedicated namespace-filter log line.
pod="$(pod_with_checksum "$before")"
[[ -n "$pod" ]] || die "no pod carries checksum $before"
logs="$(kubectl logs "$pod")"
grep -q 'Configuration loaded successfully' <<<"$logs" || die "no 'Configuration loaded' line in logs"
grep -Eq '"mode": ?"allow"' <<<"$logs" || die "startup log does not show namespaceFilter mode allow"
echo "ok: startup log shows the allow filter"

step "helm upgrade to deny"
helm upgrade "$release" "$root" -f "$root/ci/kind-values.yaml" \
  --set config.kube.namespaceFilter.mode=deny
after="$(checksum)"
[[ -n "$before" && "$before" != "$after" ]] || die "checksum/config did not change ($before -> $after)"
echo "ok: checksum/config changed"
assert "upgraded ConfigMap has deny filter" "$(cm_config)" '.kube.namespaceFilter.mode == "deny"'
kubectl rollout status deploy -l "$selector" --timeout=180s \
  || die "rollout after upgrade failed"
pod="$(pod_with_checksum "$after")"
[[ -n "$pod" ]] || die "no pod carries the new checksum $after"
logs="$(kubectl logs "$pod")"
grep -Eq '"mode": ?"deny"' <<<"$logs" || die "new pod $pod log does not show mode deny"
! grep -Eq '"mode": ?"allow"' <<<"$logs" || die "new pod $pod log still shows mode allow"
echo "ok: new pod runs with the deny filter"

step "negative: allow with no namespaces is rejected at render"
if out="$(helm install bad "$root" -f "$root/ci/kind-values.yaml" \
  --set config.kube.namespaceFilter.namespaces=null 2>&1)"; then
  die "install with an empty allow list succeeded"
fi
grep -q 'config.kube.namespaceFilter.mode is "allow" but config.kube.namespaceFilter.namespaces is empty' <<<"$out" \
  || die "unexpected error: $out"
echo "ok: invalid filter rejected"

step "all e2e checks passed"
