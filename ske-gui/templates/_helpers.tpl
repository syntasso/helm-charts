\
{{- define "ske-gui.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "ske-gui.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "ske-gui.labels" -}}
app.kubernetes.io/name: {{ include "ske-gui.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: web
app.kubernetes.io/part-of: ske-gui
{{- end }}

{{- define "ske-gui.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ske-gui.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ske-gui.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- if .Values.serviceAccount.name -}}
{{ .Values.serviceAccount.name }}
{{- else -}}
{{ include "ske-gui.fullname" . }}
{{- end -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{- define "imagePullSecret" }}
{{- printf
"{\"auths\":{\"%s\":{\"username\":\"syntasso-pkg\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .Values.imageRegistry.host .Values.skeLicense (printf "syntasso-pkg:%s" .Values.skeLicense | b64enc) | b64enc }}
{{- end }}
