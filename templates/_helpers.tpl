{{/*
Expand the name of the chart.
*/}}
{{- define "nofire-edge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nofire-edge.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nofire-edge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nofire-edge.labels" -}}
helm.sh/chart: {{ include "nofire-edge.chart" . }}
{{ include "nofire-edge.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nofire-edge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nofire-edge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nofire-edge.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nofire-edge.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the image string
*/}}
{{- define "nofire-edge.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Create config name
*/}}
{{- define "nofire-edge.configName" -}}
{{- printf "%s-config" (include "nofire-edge.fullname" .) }}
{{- end }}

{{/*
Create ServiceMonitor namespace
*/}}
{{- define "nofire-edge.serviceMonitorNamespace" -}}
{{- if .Values.monitoring.serviceMonitor.namespace }}
{{- .Values.monitoring.serviceMonitor.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Edge Proxy: fully qualified app name
*/}}
{{- define "nofire-edge.edgeProxy.fullname" -}}
{{- printf "%s-edge-proxy" (include "nofire-edge.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Edge Proxy: common labels
*/}}
{{- define "nofire-edge.edgeProxy.labels" -}}
helm.sh/chart: {{ include "nofire-edge.chart" . }}
{{ include "nofire-edge.edgeProxy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Edge Proxy: selector labels
*/}}
{{- define "nofire-edge.edgeProxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nofire-edge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: edge-proxy
{{- end }}

{{/*
Edge Proxy: image string
*/}}
{{- define "nofire-edge.edgeProxy.image" -}}
{{- $repo := .Values.edgeProxy.image.repository | default "edge-proxy" -}}
{{- $tag := .Values.edgeProxy.image.tag | default .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" $repo $tag }}
{{- end }}

{{/*
Edge Proxy: service account name
*/}}
{{- define "nofire-edge.edgeProxy.serviceAccountName" -}}
{{- include "nofire-edge.edgeProxy.fullname" . }}
{{- end }}

{{/*
Edge Proxy: configmap name
*/}}
{{- define "nofire-edge.edgeProxy.configName" -}}
{{- printf "%s-config" (include "nofire-edge.edgeProxy.fullname" .) }}
{{- end }}

{{- /*
nofire-edge.typedPick copies the keys named in .spec from .src into the dict
.out, coercing each to the type the Edge expects. Values given as strings (for
example via --set-string) would otherwise crash the Edge's JSON decoder.
A key is kept when present, even if falsy (false, 0, "", []); an explicit null
counts as unset. .spec maps key -> int | bool | string | nestring | strlist
(nestring: an empty string counts as unset). .path prefixes error messages.
Writes nothing itself: call it as `{{- $_ := include "nofire-edge.typedPick" (dict ...) }}`.
*/ -}}
{{- define "nofire-edge.typedPick" -}}
{{- $src := .src | default dict -}}
{{- $path := .path -}}
{{- range $k, $t := .spec -}}
{{- if and (hasKey $src $k) (not (kindIs "invalid" (index $src $k))) -}}
{{- $v := index $src $k -}}
{{- $p := printf "%s.%s" $path $k -}}
{{- if eq $t "int" -}}
{{- /* A number from a values file is a float64; toString would print 1048576 as 1.048576e+06. */ -}}
{{- if and (kindIs "float64" $v) (eq $v (floor $v)) -}}{{- $_ := set $.out $k (int64 $v) -}}
{{- else -}}
{{- if not (regexMatch "^-?[0-9]+$" (toString $v)) -}}{{- fail (printf "%s must be an integer (got %v)" $p $v) -}}{{- end -}}
{{- $_ := set $.out $k (int64 $v) -}}
{{- end -}}
{{- else if eq $t "bool" -}}
{{- if kindIs "bool" $v -}}{{- $_ := set $.out $k $v -}}
{{- else if has (toString $v) (list "true" "false") -}}{{- $_ := set $.out $k (eq (toString $v) "true") -}}
{{- else -}}{{- fail (printf "%s must be a boolean (got %v)" $p $v) -}}{{- end -}}
{{- else if or (eq $t "string") (eq $t "nestring") -}}
{{- if or (kindIs "map" $v) (kindIs "slice" $v) -}}{{- fail (printf "%s must be a string" $p) -}}{{- end -}}
{{- if or (eq $t "string") (ne (toString $v) "") -}}{{- $_ := set $.out $k (toString $v) -}}{{- end -}}
{{- else if eq $t "strlist" -}}
{{- if not (kindIs "slice" $v) -}}{{- fail (printf "%s must be a list" $p) -}}{{- end -}}
{{- range $e := $v -}}{{- if not (kindIs "string" $e) -}}{{- fail (printf "%s entry %v must be a string" $p $e) -}}{{- end -}}{{- end -}}
{{- $_ := set $.out $k $v -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /* nofire-edge.servicesJson: the Edge "services" object, with only the keys the user set. */ -}}
{{- define "nofire-edge.servicesJson" -}}
{{- $s := .Values.config.services | default dict -}}
{{- if not (kindIs "map" $s) -}}{{- fail "config.services must be a map" -}}{{- end -}}
{{- $out := dict -}}
{{- $_ := include "nofire-edge.typedPick" (dict "src" $s "path" "config.services" "out" $out "spec" (dict "workers" "int" "address" "nestring" "maxConns" "int" "readTimeout" "string" "writeTimeout" "string")) -}}
{{- $objects := dict
    "tls" (dict "enabled" "bool" "certFile" "string" "keyFile" "string" "caFile" "string" "requireClientCert" "bool" "minVersion" "string" "cipherSuites" "strlist")
    "compression" (dict "enabled" "bool" "type" "string" "level" "int")
    "handshake" (dict "timeout" "string" "contentType" "string") -}}
{{- range $name, $spec := $objects -}}
{{- $v := get $s $name -}}
{{- if and (hasKey $s $name) (not (kindIs "invalid" $v)) (not (kindIs "map" $v)) -}}{{- fail (printf "config.services.%s must be a map" $name) -}}{{- end -}}
{{- if kindIs "map" $v -}}
{{- $o := dict -}}
{{- $_ := include "nofire-edge.typedPick" (dict "src" $v "path" (printf "config.services.%s" $name) "out" $o "spec" $spec) -}}
{{- if $o -}}{{- $_ := set $out $name $o -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{- /*
nofire-edge.captureJson: the Edge configMapCapture / envCapture object for
.src (a values map; .path prefixes error messages). Starts from the Edge
defaults, so unset keys render as defaults. The Edge only logs and skips an
invalid redactKeyPatterns regex, which with clearText would send the value in
the clear, so unknown keys and bad regexes fail the render instead.
*/ -}}
{{- define "nofire-edge.captureJson" -}}
{{- $src := .src | default dict -}}
{{- $path := .path -}}
{{- if not (kindIs "map" $src) -}}{{- fail (printf "%s must be a map" $path) -}}{{- end -}}
{{- range $key, $_ := $src -}}
{{- if not (has $key (list "clearText" "captureCap" "redactKeyPatterns")) -}}
{{- fail (printf "%s has unknown key %q; supported keys are clearText, captureCap and redactKeyPatterns" $path $key) -}}
{{- end -}}
{{- end -}}
{{- $out := dict "clearText" false "captureCap" 4096 "redactKeyPatterns" list -}}
{{- $_ := include "nofire-edge.typedPick" (dict "src" $src "path" $path "out" $out "spec" (dict "clearText" "bool" "captureCap" "int" "redactKeyPatterns" "strlist")) -}}
{{- range $p := $out.redactKeyPatterns -}}
{{- /* regexMatch reports a pattern that does not compile as false, but "|^" matches "" otherwise. */ -}}
{{- if not (regexMatch (printf "(?:%s)|^" $p) "") -}}{{- fail (printf "%s.redactKeyPatterns entry %q is not a valid regex" $path $p) -}}{{- end -}}
{{- /* A pattern like "a)|(b" passes the check above; regexFind rejects it. */ -}}
{{- $_ := regexFind $p "" -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}
