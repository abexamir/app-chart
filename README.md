# app-chart

A general-purpose Helm chart for deploying an application to Kubernetes, with **1:1 field
parity** with the [app-operator](https://github.com/abexamir/app-operator) `AppDefinition`
CRD (`appdefinition.abexamir.me/v1`).

Every key in `values.yaml` is the same name, at the same nesting path, as the matching field
in `AppDefinitionSpec`. If you know how to write an `AppDefinition`, you know how to write
this chart's values — copy a `spec:` body into `values.yaml` almost verbatim.

This chart renders native Kubernetes resources directly (Deployment, Service, Ingress, PVC,
HPA, ConfigMap, Secret, ExternalSecret, ServiceMonitor) — no controller, no CRD. Use this for
GitOps-native deployment; use app-operator for a live-reconciling control plane with a UI.

## Install

```sh
helm install my-app . -f my-values.yaml
```

See `values.yaml` for the full field reference and `ci/*.yaml` for working examples covering
every field.

## Divergences from the operator

A few operator behaviors have no faithful equivalent in a stateless template renderer:

- **`paused`**: the operator freezes reconciliation in place. Helm can't "not apply" — this
  chart renders zero resources when `paused: true`, which means `helm upgrade` will delete
  everything on the release.
- **`disk.protect`**: approximated with Helm's `lookup` function (only works against a live
  cluster; `helm template` with no cluster context always skips the PVC).
- **External-secret rollout**: the operator reconciles continuously, so it rolls pods as soon
  as ESO syncs a new value into a `spec.externalSecrets` Secret. This chart only checks (via
  `lookup`, so also skipped by `helm template`) at render time, so the rollout only happens on
  the next `helm upgrade` after a sync — there's no continuous loop to catch it sooner.
- **`externalSecretsApiVersion` / `serviceMonitorApiVersion`**: the operator auto-detects the
  best API version at reconcile time; this chart pins them in `values.yaml` since Helm can't
  introspect the cluster at render time.
- **Default SecretStore auto-provisioning**: cluster-specific infra bootstrapping the
  operator does outside the `AppDefinitionSpec` — not replicated here.

See `CLAUDE.md` for the field-parity contract this chart maintains with app-operator.
