{{- define "kirana.name" -}}{{ .Release.Name }}{{- end }}

{{- define "kirana.labels" -}}
app.kubernetes.io/name: kirana
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: kirana
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "kirana.selector" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "kirana.secretName" -}}
{{ .Values.secrets.existingSecret | default (printf "%s-secrets" .Release.Name) }}
{{- end }}

{{- define "kirana.backendImage" -}}
{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "kirana.frontendImage" -}}
{{ .Values.frontend.image.repository }}:{{ .Values.frontend.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "kirana.podSecurity" -}}
runAsNonRoot: true
seccompProfile: { type: RuntimeDefault }
{{- end }}

{{- define "kirana.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities: { drop: ["ALL"] }
{{- end }}
