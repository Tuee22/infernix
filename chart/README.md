# Infernix Helm Chart Scaffold

This directory contains the repo-owned Helm chart scaffold for the final Kind-backed deployment
path.

Current scope:

- repo-owned service, web, edge-route, and generated-demo-config templates
- shared values for runtime mode, route publication, and the mandatory local HA replica targets
- stable mount-path contract for `ConfigMap/infernix-demo-config` at `/opt/build/`

Still open:

- wiring external Harbor, MinIO, Pulsar, and ingress-nginx chart dependencies
- driving `infernix cluster up` from Helm rather than the current compatibility layer
- validating the rendered chart on the final Kind substrate
