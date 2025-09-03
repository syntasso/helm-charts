{{- define "imagePullSecret" }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"syntasso-pkg\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .Values.imageRegistry.host .Values.skeLicense (printf "syntasso-pkg:%s" .Values.skeLicense | b64enc) | b64enc }}
{{- end }}
