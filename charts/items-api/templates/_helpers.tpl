{{- define "items-api.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "items-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "items-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "items-api.labels" -}}
{{ include "items-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
