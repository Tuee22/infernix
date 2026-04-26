# Infernix Helm Chart

This directory contains the repo-owned Helm deployment assets used by `infernix cluster up` on the
supported Kind path.

Current scope:

- repo-owned templates for the edge proxy, demo workload, service workload, publication state,
  generated demo-config, service PVC, and Harbor or MinIO or Pulsar gateway workloads
- locked Harbor, MinIO, Pulsar, and ingress-nginx dependencies in `Chart.yaml` and `Chart.lock`
- shared values for runtime mode, route publication, Harbor-backed image coordinates, mandatory
  local HA replica targets, and the manual `infernix-manual` storage contract

Runtime contract:

- `infernix cluster up` bootstraps the declared Helm repositories, renders this chart, and deploys
  it on the active Kind cluster
- cluster-resident service and `infernix-demo` workloads mount `ConfigMap/infernix-demo-config`
  read-only at `/opt/build/`
- `chart/templates/deployment-demo.yaml` and `chart/templates/service-demo.yaml` gate the
  `infernix-demo` workload on `.Values.demo.enabled`, driven from the active `.dhall` `demo_ui`
  flag
- non-Harbor workloads pull Harbor-published image references selected through chart values
- the separate `web/Dockerfile` image remains Harbor-published for Playwright execution, but it is
  not deployed as a chart workload
