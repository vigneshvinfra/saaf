{{/*
The chart always deploys under a single release name ("underwriting-agent"), so the name is simply the chart name
*/}}
{{- define "agent.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Common labels on every object. */}}
{{- define "agent.labels" -}}
app.kubernetes.io/name: {{ include "agent.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Labels used in selectors — must stay stable across releases. */}}
{{- define "agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agent.name" . }}
{{- end -}}

{{/* ServiceAccount name — must match the EKS Pod Identity association in Terraform. */}}
{{- define "agent.serviceAccountName" -}}
{{- default (include "agent.name" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/* Image tag: explicit value wins, else chart appVersion. */}}
{{- define "agent.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}
