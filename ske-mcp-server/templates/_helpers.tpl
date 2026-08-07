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

{{/*
Whether a static bearer token is configured, by either route.
*/}}
{{- define "ske-mcp-server.staticTokenEnabled" -}}
{{- if or (ne (trim .Values.auth.token) "") (ne (trim .Values.auth.existingSecret.name) "") }}true{{- end }}
{{- end }}

{{/*
Whether OIDC is configured. Keyed on the issuer alone; validate enforces that the resource URL
accompanies it, so anything downstream can test one field.
*/}}
{{- define "ske-mcp-server.oidcEnabled" -}}
{{- if ne (trim .Values.auth.oidc.issuer) "" }}true{{- end }}
{{- end }}

{{- define "ske-mcp-server.validate" -}}
{{- $hasToken := ne (trim .Values.auth.token) "" }}
{{- $hasExisting := ne (trim .Values.auth.existingSecret.name) "" }}
{{- if and $hasToken $hasExisting }}
{{- fail "auth: set exactly one of auth.token or auth.existingSecret.name, not both" }}
{{- end }}

{{- $hasIssuer := ne (trim .Values.auth.oidc.issuer) "" }}
{{- $hasResourceURL := ne (trim .Values.auth.oidc.resourceURL) "" }}
{{- if ne $hasIssuer $hasResourceURL }}
{{- fail "auth.oidc: set auth.oidc.issuer and auth.oidc.resourceURL together — the resource URL is the audience the server requires in every token, and the server refuses to start with one of the two missing" }}
{{- end }}

{{/*
The security guard. With neither mechanism configured the server has no bearer-token middleware
on /mcp, so the endpoint answers unauthenticated callers — and a chart that renders that quietly
is how it reaches a cluster. Refuse instead.
*/}}
{{- if and (not (include "ske-mcp-server.staticTokenEnabled" .)) (not $hasIssuer) }}
{{- fail "auth: configure at least one mechanism — auth.oidc.issuer plus auth.oidc.resourceURL, or auth.token/auth.existingSecret.name. With neither, /mcp is served with no authentication at all" }}
{{- end }}

{{- if ne (int .Values.replicaCount) 1 }}
{{- fail "replicaCount must be exactly 1 because MCP sessions are stored in memory" }}
{{- end }}
{{- if .Values.ingress.enabled }}
{{- if eq (trim .Values.ingress.host) "" }}
{{- fail "ingress.host is required when ingress is enabled" }}
{{- end }}
{{/*
`ingress.tls.secretName` is deliberately NOT required. Where TLS terminates upstream of the
cluster — an AWS load balancer holding an ACM certificate, say — there is no TLS Secret to name,
and requiring one made this chart impossible to install there. The Ingress omits the `tls` block
entirely in that case rather than emitting an empty secretName.
*/}}
{{- end }}
{{- end }}

