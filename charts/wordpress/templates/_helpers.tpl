{{- define "wordpress.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Stable identity labels used for Deployment/Service selectors and pod
template labels. These MUST NOT change across chart versions/upgrades,
since spec.selector is immutable on both Deployments and Services.
*/}}
{{- define "wordpress.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Full labels (includes the chart version) for use ONLY on metadata.labels
of top-level objects, never on anything used as a selector.
*/}}
{{- define "wordpress.labels" -}}
{{ include "wordpress.selectorLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
