# AGENTS.md

This file provides guidance to coding agents (Claude Code, Codex, etc.) when working with code
in this repository.

## What this is

A Helm chart that reproduces [app-operator](https://github.com/abexamir/app-operator)'s
`AppDefinition` reconcile logic (`internal/controller/reconcile_*.go`) as plain Go templates
rendering native Kubernetes resources — no controller, no CRD. `values.yaml` is the same
shape as `AppDefinitionSpec` (`api/v1/appdefinition_types.go` in that repo): same field
names, same nesting, same defaults.

## Field parity contract — read this before touching either repo

**app-operator's `AppDefinitionSpec` and this chart's `values.yaml` must stay in lockstep.**
When you change one repo, change the other in the same session/PR:

- New/removed/renamed field in `AppDefinitionSpec` → same change in `values.yaml` + wire it
  into the relevant `templates/*.yaml`.
- New default (`+kubebuilder:default` or reconcile-time) → matching default here.
- New CEL validation rule on the CRD → add the equivalent check to `app-chart.validate` in
  `templates/_helpers.tpl`.
- Changed resource-building logic in a `reconcile_*.go` file → update the matching template:

  | app-operator                   | app-chart                                              |
  |---------------------------------|---------------------------------------------------------|
  | `reconcile_deployment.go`       | `templates/deployment.yaml` + container/probe/volume helpers |
  | `reconcile_service.go`          | `templates/service.yaml`                                |
  | `reconcile_ingress.go`          | `templates/ingress.yaml` — one Ingress **per domain** (not one shared Ingress with a rule per domain), required for per-domain `router.middlewares` scoping |
  | `reconcile_middleware.go`       | `templates/middleware.yaml` — one Traefik `Middleware` CR per domain per enabled kind |
  | `reconcile_pvc.go`              | `templates/pvc.yaml`                                    |
  | `reconcile_hpa.go`              | `templates/hpa.yaml`                                    |
  | `reconcile_configmaps.go`       | `templates/configmap.yaml`                               |
  | `reconcile_secrets.go`          | `templates/secret.yaml`                                  |
  | `reconcile_externalsecrets.go`  | `templates/externalsecret.yaml`                          |
  | `reconcile_servicemonitor.go`   | `templates/servicemonitor.yaml`                          |
  | `helpers.go` (naming funcs)     | matching named templates in `_helpers.tpl`               |

  `reconcile_defaultsecretstore.go` and `reconcile_status.go` have no counterpart — see
  README.md's "Divergences" section for why.

## Template style

- **Never hand-indent nested YAML across `if`/`range` boundaries with `nindent`/`indent`
  chains** — Go template whitespace trimming is easy to get subtly wrong (phantom blank
  lines). Build a native Sprig `list`/`dict` and emit it with `toYaml` in one shot instead.
  Every non-trivial builder in `_helpers.tpl` follows this pattern.
- To nest a `toYaml`-rendered string back into a parent dict, round-trip with `fromYaml`
  (mapping) or `fromYamlArray` (list).
- Validate template changes: `helm template x . -f ci/full-values.yaml | kubectl apply
  --dry-run=client -f -` against a real cluster context.
- `ci/*.yaml` holds full-coverage values files — extend them when you add a field.

## Commands

```sh
helm lint .
helm template x . -f ci/full-values.yaml
helm template x . -f ci/stateful-values.yaml
```

## Releasing

This chart isn't tied to any one Helm repository — release the package wherever your
consumers pull from. General steps:

1. Bump `version` in `Chart.yaml` (semver, independent of `appVersion`): patch for
   template-only fixes, minor for new `values.yaml` fields, major for a breaking change to an
   existing field's shape or default. Bump `appVersion` too if it tracks a new app-operator
   release.
2. `helm lint .` and validate against a real cluster context: `helm template x . -f
   ci/full-values.yaml | kubectl apply --dry-run=client -f -`.
3. `git tag vX.Y.Z && git push --tags`.
4. `helm package .` — produces `app-chart-X.Y.Z.tgz`.
5. Push the package to your Helm repository. The exact command depends on what the repo is:
   - **OCI registry**: `helm push app-chart-X.Y.Z.tgz oci://<registry>/<path>`.
   - **ChartMuseum-API repo**: `helm cm-push` (helm-push plugin) or `helm push` if it's an OCI
     front for the same store.
   - **Nexus-style hosted repo** (no ChartMuseum API — a raw `PUT` with the filename in the
     URL): `curl -u <user>:<password> --upload-file app-chart-X.Y.Z.tgz
     <repo-url>/app-chart-X.Y.Z.tgz`.

   Never overwrite an already-published version — bump first. Hosted repos with `writePolicy:
   ALLOW` (Nexus) will silently accept the overwrite, breaking anyone already pinned to that
   version.
