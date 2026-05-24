{{/*
──────────────────────────────────────────────
Naming convention: {chart}-{component}-{environment}
e.g. vyking-apps-backend-production

All names are truncated to 63 chars (K8s DNS label limit).
──────────────────────────────────────────────
*/}}

{{/*
Environment suffix — appended to every resource name.
Source: global.environment from values.yaml (injected by ArgoCD/Terraform).
*/}}
{{- define "vyking-apps.env" -}}
{{- .Values.global.environment | default "local" }}
{{- end }}

{{/*
Base name including environment.
e.g. vyking-apps-production
*/}}
{{- define "vyking-apps.name" -}}
{{- printf "%s-%s" (default .Chart.Name .Values.nameOverride) (include "vyking-apps.env" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart label.
*/}}
{{- define "vyking-apps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource.
Includes environment so resources are identifiable at a glance.
*/}}
{{- define "vyking-apps.labels" -}}
helm.sh/chart: {{ include "vyking-apps.chart" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- /* managed-by, environment, project, owner come from global.commonLabels below */}}
{{- with .Values.global.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Backend resource name: vyking-apps-backend-production
*/}}
{{- define "vyking-apps.backend.name" -}}
{{- printf "backend-%s" (include "vyking-apps.env" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Backend selector labels (stable — used by Services, so must NOT include
version or environment to avoid selector drift on upgrades).
*/}}
{{- define "vyking-apps.backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vyking-apps.backend.name" . }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Frontend resource name: frontend-production
*/}}
{{- define "vyking-apps.frontend.name" -}}
{{- printf "frontend-%s" (include "vyking-apps.env" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Frontend selector labels.
*/}}
{{- define "vyking-apps.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vyking-apps.frontend.name" . }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Deletion protection annotation.
Applied to PVCs, Deployments, and Services in protected environments.
Admission webhooks (e.g. OPA Gatekeeper) can enforce this annotation.
*/}}
{{- define "vyking-apps.protectionAnnotations" -}}
{{- if or (eq .Values.global.environment "production") (eq .Values.global.environment "staging") }}
vyking.io/deletion-protected: "true"
vyking.io/environment: {{ .Values.global.environment }}
{{- else }}
vyking.io/deletion-protected: "false"
vyking.io/environment: {{ .Values.global.environment }}
{{- end }}
{{- end }}
