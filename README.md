# Infernix

Infernix is a Haskell inference control plane for running heterogeneous model runtimes behind one
typed operator surface.

It handles orchestration, model resolution, artifact delivery, request routing, runtime
supervision, and browser-facing manual inference while leaving execution kernels to the best
runtime for each model family.

## Highlights

- one Haskell binary: `infernix`
- one Kind and Helm workflow for local validation
- one mandatory local HA topology: Harbor, MinIO, and Pulsar on Kind
- one local Harbor registry as the image source for every non-Harbor pod
- one manual persistent-storage doctrine rooted at `./.data/`
- one PureScript webapp, deployed through Helm, with Haskell-owned frontend contracts
- one browser-based manual inference workbench for any registered model
- one validation surface spanning `fourmolu`, `cabal-fmt`, `hlint`, unit tests, integration tests,
  `purescript-spec`, and Playwright

## What Infernix Does

Infernix does not reimplement model kernels. It coordinates them.

- resolves logical models against durable manifest and artifact metadata
- fetches or verifies durable artifacts in MinIO
- materializes runtime-local cache state from durable sources
- launches and supervises engine-specific workers
- routes requests to the right engine and model lane
- stores large outputs in MinIO and returns references when appropriate
- exposes a web UI for manually running inference against any registered model

## Operator Modes

Infernix supports two control-plane modes:

| Mode | Primary use | Control plane |
|------|-------------|---------------|
| Apple Silicon | host-native local development and testing | `./.build/infernix` |
| Containerized Linux | containerized local validation and CI-style execution | `docker compose run --rm infernix infernix ...` |

On Apple Silicon, `infernix` may install missing supported host prerequisites through the operator
flow, including Homebrew `poetry` and other declared Python dependencies required by repo-owned
runtime paths.

## Local Architecture

The supported local platform is built around:

- one Kind cluster used for repository validation and local integration testing
- one reverse-proxied localhost edge port for the UI, API, Harbor, MinIO, and Pulsar browser surfaces
- one manual storage class backed by repo-owned PVs under `./.data/`
- one local Harbor registry used by every cluster pod except Harbor's own bootstrap path
- one cluster-resident webapp image, built from a separate webapp binary via `web/Dockerfile`, that
  also owns Playwright browser dependencies
- one repo-owned `cabal.project` that keeps host-native Cabal artifacts under `./.build/`
- one repo-local kubeconfig managed under the active build-output location rather than the user's
  global kubeconfig

The web UI always runs in the cluster, even when the Haskell daemon runs host-native on Apple
Silicon.

## Quick Start

### Apple Silicon

Build the binary with the repo-owned Cabal defaults, bring up the test cluster, run the full suite,
then tear it down:

```bash
# Build the infernix binary using the repo-owned Cabal defaults.
cabal build infernix
# Reconcile the Kind test cluster, storage, images, and Helm workloads.
./.build/infernix cluster up
# Report cluster health, edge routing, and durable-state status.
./.build/infernix cluster status
# Query the cluster through the repo-local kubeconfig wrapper.
./.build/infernix kubectl get pods -A
# Run lint, unit, integration, and E2E validation.
./.build/infernix test all
# Tear down the Kind cluster while preserving authoritative data under ./.data.
./.build/infernix cluster down
```

The repo-owned `cabal.project` keeps generated host-native artifacts under `./.build/`. `cluster
up` auto-generates the test Dhall config needed for supported workflows, enables all models
appropriate for the active mode under test, writes the repo-local kubeconfig to
`./.build/infernix.kubeconfig`, and does not mutate `$HOME/.kube/config`.

### Containerized Linux

Build the outer image, bring up the test cluster, run the full suite, then tear it down:

```bash
# Build the outer control-plane image.
docker compose build infernix
# Reconcile the Kind test cluster, storage, images, and Helm workloads.
docker compose run --rm infernix infernix cluster up
# Report cluster health, edge routing, and durable-state status.
docker compose run --rm infernix infernix cluster status
# Query the cluster through the repo-local kubeconfig wrapper.
docker compose run --rm infernix infernix kubectl get pods -A
# Run lint, unit, integration, and E2E validation.
docker compose run --rm infernix infernix test all
# Tear down the Kind cluster while preserving authoritative data under ./.data.
docker compose run --rm infernix infernix cluster down
```

Containerized builds keep all generated artifacts under `/opt/build/infernix`. Supported outer
container workflows and Dockerfile `cabal` invocations pass `--builddir=/opt/build/infernix`
explicitly so build output never lands in the mounted repository tree. The generated test Dhall
config and repo-local kubeconfig also live under `/opt/build/infernix` on this path.

## CLI Surface

The canonical supported CLI surface is:

- `infernix service`
- `infernix cluster up`
- `infernix cluster down`
- `infernix cluster status`
- `infernix kubectl ...`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`
- `infernix docs check`

Every repo-owned lifecycle, validation, and docs command other than `infernix service` is
declarative and idempotent. `infernix kubectl ...` is a scoped wrapper around upstream `kubectl`,
not a parallel lifecycle surface.

## Runtime and Image Flow

- `cluster up` is the supported test-cluster bring-up command
- `cluster up` declaratively reconciles Kind, manual storage, Harbor-backed images, Helm workloads,
  repo-local kubeconfig, and generated test configuration
- `cluster up` mirrors required third-party images into Harbor before deploying non-Harbor workloads
- `cluster up` builds repo-owned images, including the webapp image through `web/Dockerfile`, and
  publishes them to Harbor before Helm rollout
- every non-Harbor pod pulls from local Harbor
- Harbor is the only allowed direct-upstream bootstrap exception
- `cluster up` always deploys the mandatory local HA topology: 3x Harbor application-plane services
  where the selected chart supports them, 4x MinIO, and 3x Pulsar HA surfaces where the selected
  chart supports them
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  as needed for local Kind scheduling
- `cluster down` removes cluster state without deleting authoritative data under `./.data/`

## Storage Model

Local durability is explicit.

- default storage classes are deleted during cluster bootstrap
- the only supported persistent storage class is the repo-owned `kubernetes.io/no-provisioner`
  class, tentatively named `infernix-manual`
- PVCs are created only by Helm-owned StatefulSets or chart-owned persistence templates
- PVs are created only by `infernix` lifecycle logic
- PVs bind deterministically into `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- explicit PV-to-PVC binding guarantees clean `cluster down` and `cluster up` rebinding behavior
- storage reconciliation is part of `cluster up`; there is no separate storage reconcile command

MinIO is authoritative for durable artifacts and large outputs. Local cache state is derived and
rebuildable.

## Web UI and Testing

The browser surface is a PureScript application with Haskell-generated shared contracts.

- Haskell types remain the source of truth for the frontend contract
- the webapp is a separate binary from `infernix` and is built through `web/Dockerfile`
- frontend contract generation happens during the webapp image build
- the webapp is deployed through repo-owned Helm chart templates and values
- `purescript-spec` covers contract and view behavior
- Playwright runs from the same image that serves the web UI
- the UI can submit manual inference requests against any registered model

## Documentation

- `documents/` is the canonical home for governed architecture, development, engineering,
  operations, reference, tools, and research documentation
- `DEVELOPMENT_PLAN/` contains the execution-ordered buildout plan and phase closure criteria
- start with [documents/README.md](documents/README.md) for the suite index
- use [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) for phase order and closure rules

## Contributing

Contributions should keep implementation, tests, and docs aligned in the same change.

- use `documents/` for architecture, operator, and development guidance
- use `DEVELOPMENT_PLAN/` for phase ordering, scope, and closure criteria
- run `python3 tools/docs_check.py`, `infernix test lint`, and the relevant `infernix test ...`
  targets before opening changes

## License

[MIT](LICENSE)
