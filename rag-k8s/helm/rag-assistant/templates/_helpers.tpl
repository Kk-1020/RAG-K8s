{{/*
Expand the name of the chart.
*/}}
{{- define "rag-assistant.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rag-assistant.fullname" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "rag-assistant.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "rag-assistant.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels for rag-api pods.
*/}}
{{- define "rag-assistant.ragApi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rag-assistant.name" . }}
app.kubernetes.io/component: rag-api
{{- end }}

{{/*
Selector labels for rest-backend pods.
*/}}
{{- define "rag-assistant.restBackend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rag-assistant.name" . }}
app.kubernetes.io/component: rest-backend
{{- end }}
