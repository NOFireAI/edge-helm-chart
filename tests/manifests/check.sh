#!/usr/bin/env bash
# Checks the standalone manifests.yaml: the embedded config.json is valid and
# lists endpoints, k8services and the IngressClass, Gateway API and Traefik
# routing kinds but not services (its list differs from the chart default,
# which has services), the ClusterRole can read endpoints and the CronJob,
# PriorityClass, RBAC, Calico, IngressClass, Gateway API and Traefik kinds,
# can get and list the admission webhook configurations, and the image tag
# matches the chart appVersion. Needs yq and jq.
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
check "kube.resources has ingressclasses" jq -e '.kube.resources | index("ingressclasses")' <<<"$cfg"
check "kube.resources has Gateway API httproutes and referencegrants" \
  jq -e '(.kube.resources | index("httproutes")) and (.kube.resources | index("referencegrants"))' <<<"$cfg"
check "kube.resources has Traefik ingressroutes and traefikservices" \
  jq -e '(.kube.resources | index("ingressroutes")) and (.kube.resources | index("traefikservices"))' <<<"$cfg"
check "kube.resources has no services" jq -e '.kube.resources | index("services") | not' <<<"$cfg"

role="$(yq -o=json 'select(.kind == "ClusterRole")' "$file")"
check "ClusterRole core rule has endpoints" \
  jq -e '.rules[] | select(.apiGroups == [""]) | .resources | index("endpoints")' <<<"$role"
check "ClusterRole reads cronjobs" \
  jq -e '.rules[] | select(.apiGroups == ["batch"]) | .resources | index("cronjobs")' <<<"$role"
check "ClusterRole reads priorityclasses" \
  jq -e '.rules[] | select(.apiGroups == ["scheduling.k8s.io"]) | .resources | index("priorityclasses")' <<<"$role"
check "ClusterRole reads clusterrolebindings" \
  jq -e '.rules[] | select(.apiGroups == ["rbac.authorization.k8s.io"]) | .resources | index("clusterrolebindings")' <<<"$role"
check "ClusterRole reads Calico ipamconfigs" \
  jq -e '.rules[] | select(.apiGroups == ["crd.projectcalico.org"]) | .resources | index("ipamconfigs")' <<<"$role"
check "ClusterRole reads ingressclasses" \
  jq -e '.rules[] | select(.apiGroups == ["networking.k8s.io"]) | .resources | index("ingressclasses")' <<<"$role"
check "ClusterRole reads Gateway API httproutes and referencegrants" \
  jq -e '.rules[] | select(.apiGroups == ["gateway.networking.k8s.io"]) | (.resources | index("httproutes")) and (.resources | index("referencegrants"))' <<<"$role"
check "ClusterRole reads Traefik ingressroutes and traefikservices" \
  jq -e '.rules[] | select(.apiGroups == ["traefik.io", "traefik.containo.us"]) | (.resources | index("ingressroutes")) and (.resources | index("traefikservices"))' <<<"$role"
check "ClusterRole gets and lists both admission webhook configuration kinds" \
  jq -e '.rules[] | select(.apiGroups == ["admissionregistration.k8s.io"])
    | (.resources | index("mutatingwebhookconfigurations")) and (.resources | index("validatingwebhookconfigurations"))
    and .verbs == ["get", "list"]' <<<"$role"

env="$(yq -o=json 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env' "$file")"
check "edge container sets GODEBUG=multipathtcp=0" \
  jq -e '.[] | select(.name == "GODEBUG" and .value == "multipathtcp=0")' <<<"$env"

app_version="$(yq -r .appVersion "$root/Chart.yaml")"
images="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[].image' "$file")"
check "nofireai/edge image tag is appVersion $app_version" grep -Fxq "nofireai/edge:$app_version" <<<"$images"

exit "$fail"
