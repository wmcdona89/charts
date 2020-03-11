{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "jenkins.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Allow the release namespace to be overridden for multi-namespace deployments in combined charts.
*/}}
{{- define "jenkins.namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{- define "jenkins.master.slaveKubernetesNamespace" -}}
  {{- if .Values.master.slaveKubernetesNamespace -}}
    {{- tpl .Values.master.slaveKubernetesNamespace . -}}
  {{- else -}}
    {{- if .Values.namespaceOverride -}}
      {{- .Values.namespaceOverride -}}
    {{- else -}}
      {{- .Release.Namespace -}}
    {{- end -}}
  {{- end -}}
{{- end -}}


{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "jenkins.fullname" -}}
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
{{- end -}}

{{/*
Returns the Jenkins URL
*/}}
{{- define "jenkins.url" -}}
{{- if .Values.master.jenkinsUrl }}
  {{- .Values.master.jenkinsUrl }}
{{- else }}
  {{- if .Values.master.ingress.hostName }}
    {{- if .Values.master.ingress.tls }}
      {{- default "https" .Values.master.jenkinsUrlProtocol }}://{{ .Values.master.ingress.hostName }}{{ default "" .Values.master.jenkinsUriPrefix }}
    {{- else }}
      {{- default "http" .Values.master.jenkinsUrlProtocol }}://{{ .Values.master.ingress.hostName }}{{ default "" .Values.master.jenkinsUriPrefix }}
    {{- end }}
  {{- else }}
      {{- default "http" .Values.master.jenkinsUrlProtocol }}://{{ template "jenkins.fullname" . }}:{{.Values.master.servicePort}}{{ default "" .Values.master.jenkinsUriPrefix }}
  {{- end}}
{{- end}}
{{- end -}}

{{/*
Returns configuration as code default config
*/}}
{{- define "jenkins.casc.defaults" -}}
jenkins:
  disableRememberMe: false
  remotingSecurity:
    enabled: true
  mode: NORMAL
  numExecutors: {{ .Values.master.numExecutors }}
  projectNamingStrategy: "standard"
  markupFormatter:
    {{- if .Values.master.enableRawHtmlMarkupFormatter }}
    rawHtml:
      disableSyntaxHighlighting: true
    {{- else }}
      "plainText"
    {{- end }}
  clouds:
  - kubernetes:
      containerCapStr: "{{ .Values.agent.containerCap }}"
      {{- if .Values.master.slaveKubernetesNamespace }}
      jenkinsTunnel: "{{ template "jenkins.fullname" . }}-agent.{{ template "jenkins.namespace" . }}:{{ .Values.master.slaveListenerPort }}"
      jenkinsUrl: "http://{{ template "jenkins.fullname" . }}.{{ template "jenkins.namespace" . }}:{{.Values.master.servicePort}}{{ default "" .Values.master.jenkinsUriPrefix }}"
      {{- else }}
      jenkinsTunnel: "{{ template "jenkins.fullname" . }}-agent:{{ .Values.master.slaveListenerPort }}"
      jenkinsUrl: "http://{{ template "jenkins.fullname" . }}:{{.Values.master.servicePort}}{{ default "" .Values.master.jenkinsUriPrefix }}"
      {{- end }}
      maxRequestsPerHostStr: "32"
      name: "kubernetes"
      namespace: "{{ template "jenkins.master.slaveKubernetesNamespace" . }}"
      serverUrl: "https://kubernetes.default"
      {{- if .Values.agent.enabled }}
      templates:
      {{- include "jenkins.agent-jcasc" . | nindent 8 }}
      {{- end }}
  {{- if .Values.master.csrf.defaultCrumbIssuer.enabled }}
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: {{ if .Values.master.csrf.defaultCrumbIssuer.proxyCompatability }}true{{ else }}false{{- end }}
  {{- end }}
security:
  apiToken:
    creationOfLegacyTokenEnabled: false
    tokenGenerationOnCreationEnabled: false
    usageStatisticsEnabled: true
unclassified:
  location:
    adminAddress: {{ default "" .Values.master.jenkinsAdminEmail }}
    url: {{ template "jenkins.url" . }}
{{- end -}}

{{- define "jenkins.kubernetes-version" -}}
  {{- if .Values.master.installPlugins -}}
    {{- range .Values.master.installPlugins -}}
      {{ if hasPrefix "kubernetes:" . }}
        {{- $split := splitList ":" . }}
        {{- printf "%s" (index $split 1 ) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "jenkins.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "jenkins.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account for Jenkins agents to use
*/}}
{{- define "jenkins.serviceAccountAgentName" -}}
{{- if .Values.serviceAccountAgent.create -}}
    {{ default (printf "%s-%s" (include "jenkins.fullname" .) "agent") .Values.serviceAccountAgent.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccountAgent.name }}
{{- end -}}
{{- end -}}

{{/*
Returns agent (podTemplate) configuration as code
*/}}
{{- define "jenkins.agent-jcasc" -}}
{{- if .Values.agent.enabled -}}
- name: "{{ .Values.agent.podName }}"
  containers:
    - name: "{{ .Values.agent.sideContainerName }}"
      alwaysPullImage: {{ .Values.agent.alwaysPullImage }}
      {{- if .Values.agent.args }}
      args: "{{ .Values.agent.args }}"
      {{- else }}
      args: "^${computer.jnlpmac} ^${computer.name}"
      {{- end }}
      {{- if not ( kindIs "invalid" .Values.agent.command ) }}
      command: {{ .Values.agent.command | quote }}
      {{- end }}
      envVars:
        - containerEnvVar:
            key: "JENKINS_URL"
            value: "http://{{ template "jenkins.fullname" . }}.{{ template "jenkins.namespace" . }}.svc.{{.Values.clusterZone}}:{{.Values.master.servicePort}}{{ default "" .Values.master.jenkinsUriPrefix }}"
      {{- if .Values.agent.imageTag }}
      image: "{{ .Values.agent.image }}:{{ .Values.agent.imageTag }}"
      {{- else }}
      image: "{{ .Values.agent.image }}:{{ .Values.agent.tag }}"
      {{- end }}
      privileged: "{{- if .Values.agent.privileged }}true{{- else }}false{{- end }}"
      {{- if .Values.agent.resources }}
      {{- if .Values.agent.resources.limits }}
      resourceLimitCpu: {{.Values.agent.resources.limits.cpu}}
      resourceLimitMemory: {{.Values.agent.resources.limits.memory}}
      {{- end }}
      {{- if .Values.agent.resources.requests }}
      resourceRequestCpu: {{.Values.agent.resources.requests.cpu}}
      resourceRequestMemory: {{.Values.agent.resources.requests.memory}}
      {{- end }}
      {{- end }}
      ttyEnabled: {{ .Values.agent.TTYEnabled }}
      workingDir: {{ .Values.agent.workingDir }}
  idleMinutes: {{ .Values.agent.idleMinutes }}
  instanceCap: 2147483647
  {{- if .Values.agent.imagePullSecretName }}
  imagePullSecrets:
    - name: {{ .Values.agent.imagePullSecretName }}
  {{- end }}
  label: "{{ .Release.Name }}-{{ .Values.agent.componentName }} {{ .Values.agent.customJenkinsLabels  | join " " }}"
  nodeUsageMode: "NORMAL"
  podRetention: {{ .Values.agent.podRetention }}
  showRawYaml: true
  serviceAccount: "{{ include "jenkins.serviceAccountAgentName" . }}"
  slaveConnectTimeoutStr: "{{ .Values.agent.slaveConnectTimeout }}"
  {{- if .Values.agent.volumes }}
  volumes:
  {{- tpl ( toYaml .Values.agent.volumes | trim ) . | nindent 4 }}
  {{- end }}
  {{- if .Values.agent.yamlTemplate }}
  yaml: |-
  {{- tpl ( trim .Values.agent.yamlTemplate ) . | nindent 4 }}
  {{- end }}
  yamlMergeStrategy: "override"
{{- end -}}
{{- end -}}
