{{- define "homelab-app.name" -}}
{{- .Values.metadata.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "homelab-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homelab-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "homelab-app.labels" -}}
{{ include "homelab-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "homelab-app.probe" -}}
{{- $probe := . -}}
{{- if hasKey $probe "http" }}
httpGet:
  path: {{ $probe.path | quote }}
  port: {{ $probe.http }}
{{- else if hasKey $probe "grpc" }}
grpc:
  port: {{ $probe.grpc }}
{{- else if hasKey $probe "exec" }}
exec:
  command:
    {{- toYaml $probe.exec | nindent 4 }}
{{- else if hasKey $probe "tcp" }}
tcpSocket:
  port: {{ $probe.tcp }}
{{- end }}
initialDelaySeconds: {{ dig "initialDelaySeconds" 20 $probe }}
timeoutSeconds: {{ dig "timeoutSeconds" 5 $probe }}
periodSeconds: {{ dig "periodSeconds" 5 $probe }}
successThreshold: {{ dig "successThreshold" 1 $probe }}
failureThreshold: {{ dig "failureThreshold" 5 $probe }}
{{- end -}}

{{- define "homelab-app.volumeMount" -}}
- name: {{ .volumeName }}
  {{- if kindIs "string" .mount }}
  mountPath: {{ .mount | quote }}
  {{- else }}
  mountPath: {{ .mount.mountPath | quote }}
  subPath: {{ .mount.subPath | quote }}
  {{- end }}
  {{- if or (hasKey .volume "configMap") (hasKey .volume "secret") }}
  readOnly: true
  {{- end }}
{{- end -}}

{{- define "homelab-app.container" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $container := .container -}}
- name: {{ $name }}
  image: {{ $container.image | quote }}
  imagePullPolicy: IfNotPresent
  {{- with $container.args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $container.ports }}
  ports:
    {{- range $portName, $portNumber := . }}
    - name: {{ $portName }}
      containerPort: {{ $portNumber }}
      protocol: TCP
    {{- end }}
  {{- end }}
  {{- if and (not (default false $container.init)) $container.probes (not (hasKey $container.probes "enabled")) }}
  startupProbe:
    {{- include "homelab-app.probe" $container.probes | nindent 4 }}
  readinessProbe:
    {{- include "homelab-app.probe" $container.probes | nindent 4 }}
  livenessProbe:
    {{- include "homelab-app.probe" $container.probes | nindent 4 }}
  {{- end }}
  {{- $hasDirectEnv := false }}
  {{- range $container.env }}
    {{- if hasKey . "name" }}
      {{- $hasDirectEnv = true }}
    {{- end }}
  {{- end }}
  {{- if $hasDirectEnv }}
  env:
    {{- range $container.env }}
    {{- if hasKey . "name" }}
    - name: {{ .name }}
      {{- if hasKey . "value" }}
      value: {{ .value | quote }}
      {{- else if hasKey . "secret" }}
      valueFrom:
        secretKeyRef:
          name: {{ .secret }}
          key: {{ default .name .key }}
      {{- else if hasKey . "configMap" }}
      valueFrom:
        configMapKeyRef:
          name: {{ .configMap }}
          key: {{ default .name .key }}
      {{- end }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- $hasEnvFrom := false }}
  {{- range $container.env }}
    {{- if and (not (hasKey . "name")) (or (hasKey . "secret") (hasKey . "configMap")) }}
      {{- $hasEnvFrom = true }}
    {{- end }}
  {{- end }}
  {{- if $hasEnvFrom }}
  envFrom:
    {{- range $container.env }}
    {{- if and (not (hasKey . "name")) (hasKey . "secret") }}
    - secretRef:
        name: {{ .secret }}
      {{- with .prefix }}
      prefix: {{ . | quote }}
      {{- end }}
    {{- else if and (not (hasKey . "name")) (hasKey . "configMap") }}
    - configMapRef:
        name: {{ .configMap }}
      {{- with .prefix }}
      prefix: {{ . | quote }}
      {{- end }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- with $container.mounts }}
  volumeMounts:
    {{- range $volumeName, $mounts := . }}
      {{- if not (hasKey $root.Values.persistence $volumeName) }}
        {{- fail (printf "containers.%s.mounts references unknown persistence key %s" $name $volumeName) }}
      {{- end }}
      {{- $volume := index $root.Values.persistence $volumeName }}
      {{- if kindIs "slice" $mounts }}
        {{- range $mount := $mounts }}
    {{- include "homelab-app.volumeMount" (dict "volumeName" $volumeName "mount" $mount "volume" $volume) | nindent 4 }}
        {{- end }}
      {{- else }}
    {{- include "homelab-app.volumeMount" (dict "volumeName" $volumeName "mount" $mounts "volume" $volume) | nindent 4 }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- with $container.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $container.extra }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
