{{- define "kratix.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else -}}
kratix-platform-controller-manager
{{- end }}
{{- end }}