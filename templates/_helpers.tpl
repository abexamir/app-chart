{{/*
Chart name.
*/}}
{{- define "app-chart.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name. This is the identity used everywhere the operator uses
appDef.Name: Deployment/Service/Ingress/PVC/HPA name, and the app.kubernetes.io/name
selector label.
*/}}
{{- define "app-chart.fullname" -}}
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
Standard labels, mirroring the operator's standardLabels().
*/}}
{{- define "app-chart.labels" -}}
app.kubernetes.io/name: {{ include "app-chart.fullname" . }}
app.kubernetes.io/instance: {{ include "app-chart.fullname" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" (include "app-chart.name" .) .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Selector labels, mirroring the operator's selectorLabels(). Immutable after creation —
never derive these from anything that can change across an upgrade.
*/}}
{{- define "app-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app-chart.fullname" . }}
{{- end -}}

{{/*
DNS-1123-ish sanitize: lowercase, replace anything outside [a-z0-9-] with '-', trim
leading/trailing '-'. Mirrors sanitizeDNS() in helpers.go.
*/}}
{{- define "app-chart.sanitizeDNS" -}}
{{- regexReplaceAll "[^a-z0-9-]" (. | lower) "-" | trimAll "-" -}}
{{- end -}}

{{/*
TLS secret name for a domain when domain.secretName is not set. Mirrors tlsSecretName().
Call with (dict "fullname" ... "domain" ...).
*/}}
{{- define "app-chart.tlsSecretName" -}}
{{- printf "%s-%s-tls" .fullname (include "app-chart.sanitizeDNS" .domain) -}}
{{- end -}}

{{/*
Resolved Secret name for a secrets[] entry: secretRef if set, else "<fullname>-<name>".
Mirrors resolvedSecretName(). Call with (dict "fullname" ... "secret" ...).
*/}}
{{- define "app-chart.resolvedSecretName" -}}
{{- if .secret.secretRef -}}
{{- .secret.secretRef -}}
{{- else -}}
{{- printf "%s-%s" .fullname .secret.name -}}
{{- end -}}
{{- end -}}

{{/*
PVC name. Mirrors pvcName().
*/}}
{{- define "app-chart.pvcName" -}}
{{- printf "%s-disk" (include "app-chart.fullname" .) -}}
{{- end -}}

{{/*
ServiceMonitor name. Mirrors serviceMonitorName() — kept distinct from the app's own
name since some clusters prune ServiceMonitors that share the workload's exact name.
*/}}
{{- define "app-chart.serviceMonitorName" -}}
{{- printf "%s-monitor" (include "app-chart.fullname" .) -}}
{{- end -}}

{{/*
Validation checks mirroring the AppDefinition CRD's CEL validation rules and other
structural invariants enforced by the Go API types. Rendered (and thus evaluated) from
deployment.yaml, which every install renders.
*/}}
{{- define "app-chart.validate" -}}
{{- if not .Values.containers -}}
{{- fail "containers: at least one container is required" -}}
{{- end -}}
{{- if .Values.disk -}}
  {{- if not .Values.disk.partitions -}}
  {{- fail "disk.partitions: at least one partition is required" -}}
  {{- end -}}
  {{- if and .Values.replicas (gt (.Values.replicas | int) 1) -}}
  {{- fail "stateful apps with persistent disk cannot have more than 1 replica; multiple instances would corrupt the shared TSDB/volume" -}}
  {{- end -}}
  {{- if and .Values.autoscaling .Values.autoscaling.enabled -}}
  {{- fail "autoscaling cannot be enabled on stateful apps with persistent disk" -}}
  {{- end -}}
{{- end -}}
{{- range .Values.secrets -}}
  {{- if and .secretRef .data -}}
  {{- fail (printf "secrets[%s]: secretRef and data are mutually exclusive" .name) -}}
  {{- end -}}
{{- end -}}
{{- range .Values.externalSecrets -}}
  {{- if and (not .data) (not .dataFrom) -}}
  {{- fail (printf "externalSecrets[%s]: at least one of data or dataFrom must be set" .name) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Shared volumes for the pod: disk, configMaps, secrets (mountPath set), externalSecrets
(mountPath set). Mirrors buildVolumes(). Built as a native list and rendered with toYaml
so no manual whitespace/indent bookkeeping is needed at the call sites.
*/}}
{{- define "app-chart.volumes" -}}
{{- $fullname := include "app-chart.fullname" . -}}
{{- $volumes := list -}}
{{- if .Values.disk -}}
{{- $volumes = append $volumes (dict "name" "app-disk" "persistentVolumeClaim" (dict "claimName" (include "app-chart.pvcName" .))) -}}
{{- end -}}
{{- range .Values.configMaps -}}
{{- $volumes = append $volumes (dict "name" (printf "cm-%s" .name) "configMap" (dict "name" (printf "%s-%s" $fullname .name) "defaultMode" 420)) -}}
{{- end -}}
{{- range .Values.secrets -}}
{{- if .mountPath -}}
{{- $volumes = append $volumes (dict "name" (printf "secret-%s" .name) "secret" (dict "secretName" (include "app-chart.resolvedSecretName" (dict "fullname" $fullname "secret" .)) "defaultMode" 420)) -}}
{{- end -}}
{{- end -}}
{{- range .Values.externalSecrets -}}
{{- if .mountPath -}}
{{- $volumes = append $volumes (dict "name" (printf "es-%s" .name) "secret" (dict "secretName" (printf "%s-%s" $fullname .name) "defaultMode" 420)) -}}
{{- end -}}
{{- end -}}
{{- if $volumes -}}
{{- toYaml $volumes -}}
{{- end -}}
{{- end -}}

{{/*
Shared volumeMounts for every container (main and init). Mirrors buildVolumeMounts().
*/}}
{{- define "app-chart.volumeMounts" -}}
{{- $mounts := list -}}
{{- if .Values.disk -}}
{{- range .Values.disk.partitions -}}
{{- $mounts = append $mounts (dict "name" "app-disk" "mountPath" .mountPath "subPath" .subPath) -}}
{{- end -}}
{{- end -}}
{{- range .Values.configMaps -}}
{{- $mounts = append $mounts (dict "name" (printf "cm-%s" .name) "mountPath" .mountPath) -}}
{{- end -}}
{{- range .Values.secrets -}}
{{- if .mountPath -}}
{{- $mounts = append $mounts (dict "name" (printf "secret-%s" .name) "mountPath" .mountPath) -}}
{{- end -}}
{{- end -}}
{{- range .Values.externalSecrets -}}
{{- if .mountPath -}}
{{- $mounts = append $mounts (dict "name" (printf "es-%s" .name) "mountPath" .mountPath) -}}
{{- end -}}
{{- end -}}
{{- if $mounts -}}
{{- toYaml $mounts -}}
{{- end -}}
{{- end -}}

{{/*
envFrom entries injecting secrets[].asEnvVars and externalSecrets[].asEnvVars.
Shared by main and init containers.
*/}}
{{- define "app-chart.envFrom" -}}
{{- $fullname := include "app-chart.fullname" . -}}
{{- $items := list -}}
{{- range .Values.secrets -}}
{{- if .asEnvVars -}}
{{- $items = append $items (dict "secretRef" (dict "name" (include "app-chart.resolvedSecretName" (dict "fullname" $fullname "secret" .)))) -}}
{{- end -}}
{{- end -}}
{{- range .Values.externalSecrets -}}
{{- if .asEnvVars -}}
{{- $items = append $items (dict "secretRef" (dict "name" (printf "%s-%s" $fullname .name))) -}}
{{- end -}}
{{- end -}}
{{- if $items -}}
{{- toYaml $items -}}
{{- end -}}
{{- end -}}

{{/*
Renders a Probe (readinessProbe/livenessProbe) dict, applying the same defaults
Kubernetes admission would apply, then emits it as YAML. Mirrors buildProbe(). Call with
the probe value (e.g. $c.readinessProbe); callers must first check that one of
httpGet/tcpSocket/exec is set.
*/}}
{{- define "app-chart.probe" -}}
{{- $p := . -}}
{{- $out := dict -}}
{{- if $p.httpGet -}}
{{- $hg := dict "path" $p.httpGet.path "port" $p.httpGet.port "scheme" ($p.httpGet.scheme | default "HTTP") -}}
{{- if $p.httpGet.host -}}{{- $_ := set $hg "host" $p.httpGet.host -}}{{- end -}}
{{- if $p.httpGet.httpHeaders -}}{{- $_ := set $hg "httpHeaders" $p.httpGet.httpHeaders -}}{{- end -}}
{{- $_ := set $out "httpGet" $hg -}}
{{- else if $p.tcpSocket -}}
{{- $ts := dict "port" $p.tcpSocket.port -}}
{{- if $p.tcpSocket.host -}}{{- $_ := set $ts "host" $p.tcpSocket.host -}}{{- end -}}
{{- $_ := set $out "tcpSocket" $ts -}}
{{- else if $p.exec -}}
{{- $_ := set $out "exec" (dict "command" $p.exec.command) -}}
{{- end -}}
{{- $_ := set $out "initialDelaySeconds" ($p.initialDelaySeconds | default 0) -}}
{{- $_ := set $out "periodSeconds" ($p.periodSeconds | default 10) -}}
{{- $_ := set $out "timeoutSeconds" ($p.timeoutSeconds | default 1) -}}
{{- $_ := set $out "successThreshold" ($p.successThreshold | default 1) -}}
{{- $_ := set $out "failureThreshold" ($p.failureThreshold | default 3) -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
Renders one main application container as a dict, then YAML. Mirrors buildContainer().
Call with (dict "root" $ "container" $c "isPrimary" <bool>).
*/}}
{{- define "app-chart.container" -}}
{{- $root := .root -}}
{{- $c := .container -}}
{{- $isPrimary := .isPrimary -}}
{{- $out := dict "name" $c.name "image" $c.image "imagePullPolicy" "IfNotPresent" "terminationMessagePath" "/dev/termination-log" "terminationMessagePolicy" "File" -}}
{{- if $c.command -}}{{- $_ := set $out "command" $c.command -}}{{- end -}}
{{- if $c.args -}}{{- $_ := set $out "args" $c.args -}}{{- end -}}
{{- if $c.env -}}{{- $_ := set $out "env" $c.env -}}{{- end -}}
{{- if $c.ports -}}
{{- $ports := list -}}
{{- range $c.ports -}}
{{- $ports = append $ports (dict "name" .name "containerPort" .containerPort "protocol" (.protocol | default "TCP")) -}}
{{- end -}}
{{- $_ := set $out "ports" $ports -}}
{{- end -}}
{{- $rp := $c.readinessProbe -}}
{{- if and $rp (or $rp.httpGet $rp.tcpSocket $rp.exec) -}}
{{- $_ := set $out "readinessProbe" (include "app-chart.probe" $rp | fromYaml) -}}
{{- end -}}
{{- $lp := $c.livenessProbe -}}
{{- if and $lp (or $lp.httpGet $lp.tcpSocket $lp.exec) -}}
{{- $_ := set $out "livenessProbe" (include "app-chart.probe" $lp | fromYaml) -}}
{{- end -}}
{{- if $c.resources -}}{{- $_ := set $out "resources" $c.resources -}}{{- end -}}
{{- if $isPrimary -}}
{{- if $root.Values.lifecycle -}}
{{- $ps := $root.Values.lifecycle.postStart -}}
{{- $pt := $root.Values.lifecycle.preStop -}}
{{- $lc := dict -}}
{{- if and $ps $ps.exec -}}{{- $_ := set $lc "postStart" (dict "exec" (dict "command" $ps.exec.command)) -}}{{- end -}}
{{- if and $pt $pt.exec -}}{{- $_ := set $lc "preStop" (dict "exec" (dict "command" $pt.exec.command)) -}}{{- end -}}
{{- if $lc -}}{{- $_ := set $out "lifecycle" $lc -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- $envFromYaml := include "app-chart.envFrom" $root -}}
{{- if $envFromYaml -}}{{- $_ := set $out "envFrom" ($envFromYaml | fromYamlArray) -}}{{- end -}}
{{- $mountsYaml := include "app-chart.volumeMounts" $root -}}
{{- if $mountsYaml -}}{{- $_ := set $out "volumeMounts" ($mountsYaml | fromYamlArray) -}}{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
Renders one init container as a dict, then YAML. Mirrors buildInitContainers() — no
ports, no lifecycle. Call with (dict "root" $ "container" $c).
*/}}
{{- define "app-chart.initContainer" -}}
{{- $root := .root -}}
{{- $c := .container -}}
{{- $out := dict "name" $c.name "image" $c.image "imagePullPolicy" "IfNotPresent" "terminationMessagePath" "/dev/termination-log" "terminationMessagePolicy" "File" -}}
{{- if $c.command -}}{{- $_ := set $out "command" $c.command -}}{{- end -}}
{{- if $c.args -}}{{- $_ := set $out "args" $c.args -}}{{- end -}}
{{- if $c.env -}}{{- $_ := set $out "env" $c.env -}}{{- end -}}
{{- if $c.resources -}}{{- $_ := set $out "resources" $c.resources -}}{{- end -}}
{{- $envFromYaml := include "app-chart.envFrom" $root -}}
{{- if $envFromYaml -}}{{- $_ := set $out "envFrom" ($envFromYaml | fromYamlArray) -}}{{- end -}}
{{- $mountsYaml := include "app-chart.volumeMounts" $root -}}
{{- if $mountsYaml -}}{{- $_ := set $out "volumeMounts" ($mountsYaml | fromYamlArray) -}}{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
SHA-256 hash of all inline configMaps[].data and secrets[].data, used as a pod template
checksum annotation to trigger a rolling restart on change. Mirrors computeConfigHash();
returns empty string when there is no inline data to hash (same short-circuit as the Go
version, so callers can gate on truthiness the same way).
*/}}
{{- define "app-chart.configHash" -}}
{{- $hasInline := false -}}
{{- range .Values.secrets -}}{{- if .data -}}{{- $hasInline = true -}}{{- end -}}{{- end -}}
{{- if or .Values.configMaps $hasInline -}}
{{- $secs := list -}}
{{- range .Values.secrets -}}{{- if .data -}}{{- $secs = append $secs . -}}{{- end -}}{{- end -}}
{{- $combined := dict "configMaps" .Values.configMaps "secrets" $secs -}}
{{- toJson $combined | sha256sum -}}
{{- end -}}
{{- end -}}

{{/*
SHA-256 hash of the current .data in every Secret spec.externalSecrets produces, read live
via `lookup` at render time. Mirrors externalSecretHash() in reconcile_deployment.go, which
the operator recomputes on every reconcile to trigger a rollout as soon as ESO syncs a new
value — this chart has no reconcile loop, so the same protection only takes effect on the
next `helm upgrade` after a sync, not automatically. `lookup` returns an empty map both when
the Secret doesn't exist yet (ESO hasn't synced) and unconditionally in `helm template`/
`--dry-run` (no live cluster to query), so this returns "" in both cases the same way
computeConfigHash's Go counterpart short-circuits on "nothing to hash yet".
*/}}
{{- define "app-chart.externalSecretHash" -}}
{{- $fullname := include "app-chart.fullname" . -}}
{{- $found := list -}}
{{- range .Values.externalSecrets -}}
{{- $secret := lookup "v1" "Secret" $.Release.Namespace (printf "%s-%s" $fullname .name) -}}
{{- if $secret -}}
{{- $found = append $found (dict "name" .name "data" $secret.data) -}}
{{- end -}}
{{- end -}}
{{- if $found -}}
{{- toJson $found | sha256sum -}}
{{- end -}}
{{- end -}}
