{{- define "ske-mcp-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ske-mcp-server.fullname" -}}
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

{{- define "ske-mcp-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ske-mcp-server.labels" -}}
helm.sh/chart: {{ include "ske-mcp-server.chart" . }}
{{ include "ske-mcp-server.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: mcp-server
app.kubernetes.io/part-of: syntasso-platform-engineering
{{- end }}

{{- define "ske-mcp-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ske-mcp-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ske-mcp-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ske-mcp-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- required "serviceAccount.name is required when serviceAccount.create is false" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "ske-mcp-server.authSecretName" -}}
{{- if .Values.auth.existingSecret.name }}
{{- .Values.auth.existingSecret.name }}
{{- else }}
{{- printf "%s-auth" (include "ske-mcp-server.fullname" .) }}
{{- end }}
{{- end }}

{{- define "ske-mcp-server.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{- define "ske-mcp-server.validate" -}}
{{- $hasToken := ne (trim .Values.auth.token) "" }}
{{- $hasExisting := ne (trim .Values.auth.existingSecret.name) "" }}
{{- if eq $hasToken $hasExisting }}
{{- fail "auth: configure exactly one of auth.token or auth.existingSecret.name" }}
{{- end }}
{{- if ne (int .Values.replicaCount) 1 }}
{{- fail "replicaCount must be exactly 1 because MCP sessions are stored in memory" }}
{{- end }}
{{- if .Values.ingress.enabled }}
{{- if eq (trim .Values.ingress.host) "" }}
{{- fail "ingress.host is required when ingress is enabled" }}
{{- end }}
{{- if eq (trim .Values.ingress.tls.secretName) "" }}
{{- fail "Ingress TLS secretName is required when ingress is enabled" }}
{{- end }}
{{- end }}
{{- end }}

