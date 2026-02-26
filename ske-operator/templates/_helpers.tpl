{{/*
Expand the name of the chart.
*/}}
{{- define "ske-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ske-operator.fullname" -}}
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
{{- define "ske-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ske-operator.labels" -}}
helm.sh/chart: {{ include "ske-operator.chart" . }}
{{ include "ske-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ske-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ske-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ske-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ske-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{- define "imagePullSecret" }}
{{- printf
"{\"auths\":{\"%s\":{\"username\":\"syntasso-pkg\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .Values.imageRegistry.host .Values.skeLicense (printf "syntasso-pkg:%s" .Values.skeLicense | b64enc) | b64enc }}
{{- end }}

{{/*
Validate cortex auth input and return normalized data.
Expected input:
  dict "config" .Values.cortexIntegration.config
Returned YAML keys:
  secretName: string
  createSecret: bool
  token: string
  url: string
*/}}
{{- define "ske-operator.cortexAuth" -}}
{{- $config := required "cortexIntegration.config is required when cortexIntegration.enabled is true" (index . "config") -}}
{{- $generatedSecretName := "cortex-crdential" -}}
{{- $token := default "" $config.token -}}
{{- $url := default "" $config.url -}}
{{- $tokenSet := ne $token "" -}}
{{- $urlSet := ne $url "" -}}
{{- $secretRefName := "" -}}
{{- if $config.secretRef -}}
{{- $secretRefName = required "Invalid cortex integration auth config: cortexIntegration.config.secretRef is set, but cortexIntegration.config.secretRef.name is empty. Set secretRef.name to an existing Secret name in kratix-platform-system." $config.secretRef.name -}}
{{- end -}}
{{- $secretRefSet := ne $secretRefName "" -}}

{{- if and $secretRefSet (or $tokenSet $urlSet) -}}
{{- fail "Invalid cortex integration auth config: provide either cortexIntegration.config.secretRef.name (use existing secret) or both cortexIntegration.config.token and cortexIntegration.config.url (auto-create secret), but not both." -}}
{{- end -}}
{{- if and $tokenSet (not $urlSet) -}}
{{- fail "Invalid cortex integration auth config: cortexIntegration.config.token is set but cortexIntegration.config.url is missing. Provide both token and url, or use secretRef.name instead." -}}
{{- end -}}
{{- if and $urlSet (not $tokenSet) -}}
{{- fail "Invalid cortex integration auth config: cortexIntegration.config.url is set but cortexIntegration.config.token is missing. Provide both token and url, or use secretRef.name instead." -}}
{{- end -}}
{{- if and (not $secretRefSet) (not (and $tokenSet $urlSet)) -}}
{{- fail "Invalid cortex integration auth config: when cortexIntegration.enabled=true, you must provide exactly one auth method: either cortexIntegration.config.secretRef.name, or both cortexIntegration.config.token and cortexIntegration.config.url." -}}
{{- end -}}

{{- if $secretRefSet -}}
secretName: {{ $secretRefName | quote }}
createSecret: false
token: ""
url: ""
{{- else -}}
secretName: {{ $generatedSecretName | quote }}
createSecret: true
token: {{ $token | quote }}
url: {{ $url | quote }}
{{- end -}}
{{- end -}}
