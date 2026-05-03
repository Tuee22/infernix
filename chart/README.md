# Infernix Helm Chart

This directory contains the repo-owned Helm deployment assets used by `infernix cluster up` on the
supported Kind path.

Current scope:

- repo-owned templates for the Gateway API surface, demo workload, service workload,
  publication state, generated demo-config, and the service PVC
- locked Harbor, MinIO, Pulsar, PostgreSQL-operator, and Envoy Gateway dependencies in
  `Chart.yaml` and `Chart.lock`
- shared values for runtime mode, HTTPRoute publication, Harbor-backed image coordinates,
  mandatory local HA replica targets, and the manual `infernix-manual` storage contract

Runtime contract:

- `infernix cluster up` bootstraps the declared Helm repositories, renders this chart, and deploys
  it on the active Kind cluster
- cluster-resident service and `infernix-demo` workloads mount `ConfigMap/infernix-demo-config`
  read-only at `/opt/build/infernix/infernix-substrate.dhall`
- `chart/templates/deployment-demo.yaml` and `chart/templates/service-demo.yaml` gate the
  `infernix-demo` workload on `.Values.demo.enabled`, driven from the active `.dhall` `demo_ui`
  flag
- routing is owned by `GatewayClass/infernix-gateway`, `Gateway/infernix-edge`, and the
  `chart/templates/httproutes/` inventory
- non-Harbor workloads pull Harbor-published runtime-image references selected through chart values
