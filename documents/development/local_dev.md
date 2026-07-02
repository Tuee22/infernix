# Local Development

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Describe the supported local operator workflows for Apple host-native and
> containerized Linux execution.

## Current Status

- Apple clean-host support reduces pre-existing host requirements to Homebrew plus ghcup and
  exposes `./bootstrap/apple-silicon.sh` as the supported stage-0 entrypoint. Docker-backed Apple
  work must use the operator's already selected native arm64 Docker daemon; the repo must not
  create or switch Docker contexts or create a Colima VM
- the Apple stage-0 bootstrap now verifies the selected ghcup-managed `ghc` and `cabal`
  executables plus Homebrew `protoc` before direct `cabal install`, so the clean-host first run
  no longer depends on rerunning the same bootstrap command after Cabal is first installed
- after `./.build/infernix` exists on Apple Silicon, supported host-native commands may reconcile
  Homebrew-managed `kind`, `kubectl`, `helm`, Node.js, the Homebrew-managed `python@3.12` formula
  and `python3.12` command, and Poetry through the supported package-manager or user-local
  bootstrap path when the active flow first needs them. They must not use cross-architecture
  emulation or provision a Docker VM or context
- `linux-cpu` and `linux-gpu` expose repo-owned `bootstrap/*.sh` entrypoints that keep host
  prerequisites probe-driven and idempotent; the CPU path stops at Docker Engine plus the Docker
  buildx and Compose plugins, and the GPU path adds only the supported NVIDIA driver and
  container-toolkit setup
- development and validation are organized by hardware cohort: operators can keep phase work on
  the current Apple Silicon or CUDA-capable Linux machine, then batch the counterpart machine's
  full-suite run at phase closure instead of switching hosts for every sprint
- the target bootstrap responsibility boundary keeps shell scripts out of Kind, Kubernetes
  manifests, and cluster workload image-pull orchestration: after prerequisites and the
  substrate-specific launcher are available, lifecycle commands are ordinary `infernix` binary
  invocations
- the lifecycle keeps Kind and `nvkind` lock-taking off repo-visible paths by using a transient
  scratch kubeconfig under the execution context's system temp directory during cluster create or
  delete, then publishing the durable repo-local kubeconfig afterward

## Apple Host-Native Flow

```bash
./bootstrap/apple-silicon.sh up
./bootstrap/apple-silicon.sh status
./bootstrap/apple-silicon.sh test
./bootstrap/apple-silicon.sh down
```

Direct reference path:

```bash
cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
./.build/infernix cluster up
./.build/infernix cluster status
./.build/infernix test all
./.build/infernix cluster down
```

The first supported Apple host-native command that needs Docker, Kubernetes tooling, Node.js,
Python, or Poetry reconciles those prerequisites automatically.

## Containerized Linux Flow

```bash
./bootstrap/linux-cpu.sh up
./bootstrap/linux-cpu.sh status
./bootstrap/linux-cpu.sh test
./bootstrap/linux-cpu.sh down
```

Direct reference path:

```bash
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster up
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster status
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster down
```

For `linux-gpu`, use `./bootstrap/linux-gpu.sh ...` as the supported entrypoint. The underlying
reference path uses the same `compose.yaml` service and prefixes the direct command with
`LAUNCHER_IMAGE=infernix-linux-gpu:local`. If the host does not already pass `nvidia-smi -L`, the
supported bootstrap installs the recommended Ubuntu compute driver, stops, and instructs the
operator to reboot before rerunning the same command.

## Cross-Hardware Development Cadence

The supported workflow keeps day-to-day phase work local to one hardware cohort whenever possible.

> **Implement in natural phase order on whichever single machine is present. The cohort gate is a
> batched wave — the only supported machine switch — not a per-sprint or per-phase trigger.** Every
> open phase and sprint has two independent axes. *Code-side closure* (Axis 1) is the implementation
> plus the machine-independent gate set — `cabal build all`, `cabal test infernix-unit`,
> `cabal test infernix-haskell-style`, `infernix lint files/docs/chart/proto`, `infernix docs
> check`, the web unit suite, and `poetry run check-code`; completed in natural order on one
> machine, it is the gate to begin the *next* phase's implementation. *Cohort sign-off* (Axis 2) is
> the hardware-specific full-suite — Apple Metal including headless Metal/Core ML materialization,
> and CUDA GPU runs — batched once per closure cycle against frozen code and tracked in
> `cohort-validation-waves.md`; it is the gate for `Done` and never the gate for moving on. **The
> next action for any open phase is always its remaining code-side closure on the machine you
> already have; do not switch machines to "validate the open phase." The machine switch happens only
> at a scheduled wave boundary, once per cohort.** A deliverable that is intrinsically
> hardware-bound — for example the Apple-only Metal runtime bridge probe and Core ML materialization
> smoke of Phase 1 Sprint 1.14 — is named as
> such in its `Code-side closure` field and is exercised inside its cohort's wave, never pre-claimed
> as machine-independent.

- Apple-owned changes use the Apple host-native bootstrap and direct `./.build/infernix` commands
  for local validation, then queue the CUDA Linux cohort for the phase closure batch.
- Linux, CUDA, chart, and outer-container changes use the `linux-gpu` bootstrap and
  `docker compose run --rm infernix infernix ...` reference path for local validation, then queue
  the Apple Silicon cohort for the phase closure batch.
- `linux-cpu` remains a portable CPU-only lane for native Linux amd64 and native Linux arm64
  hosts, but it is not exercised through Apple Silicon emulation and does not replace the CUDA
  Linux cohort for GPU-sensitive closure.
- A phase reaches full cross-hardware closure only after the Apple Silicon and CUDA Linux cohorts
  both run the relevant full-suite gates against the same phase state.

## Engine Adapter Testing

When exercising a Python-native engine adapter, Poetry materializes a local environment only for
the shared adapter project:

```bash
./.build/infernix test unit
```

## Rules

- the active substrate comes from the generated `.dhall` beside the binary rather than a CLI flag
- supported staging is binary-owned: the active lifecycle or validation command materializes or
  verifies the substrate file under the active build root, and
  `infernix internal materialize-substrate <runtime-mode>` remains the direct repair or inspection
  helper for operators and tests that need to stage the file explicitly
- supported repo-owned shell is limited to the `bootstrap/*.sh` stage-0 entrypoints; they prepare
  the host, build the Apple host binary or enter the Linux Compose launcher, and then hand off to
  the direct `infernix` command surface; they do not run `kind`, `kubectl`, `helm`, manifest
  deployment commands, cluster workload image pulls, or image publication directly
- supported stage-0 bootstrap entrypoints are restartable host prerequisite reconcilers: they
  continue in the current process only after they can verify a usable executable for any tool they
  just installed or selected, and they stop at explicit new-shell or reboot boundaries so the
  operator reruns the same bootstrap command instead of skipping ahead to a later direct command
- the target Apple host workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter test or setup path is
  exercised, and `infernix` reconciles the Homebrew-managed `python@3.12` formula and
  `python3.12` command plus a user-local `poetry` executable when that path first needs it; the
  Poetry bootstrap may reuse an already available compatible Python 3.12+ executable when one
  passes the implemented version check
- Apple Silicon workflows must not create or switch Docker contexts and must not create Colima
  VMs; Docker-backed Apple paths require the current Docker context to already point at a native
  arm64 Docker daemon
- cross-architecture emulation is not a supported development or validation path
- on Linux, routed E2E runs Playwright inside the substrate image on Docker's private `kind`
  network against the Kind control-plane DNS instead of `host.docker.internal`; Apple host-native
  routed E2E uses host `npm exec` with the same typed fixture and is covered by the Apple cohort
  validation batch
- on Apple, retained Kind state under `./.data/kind/apple-silicon/` is replayed into and out of
  the worker instead of being bind-mounted, so large retained state can make `up`, `test`, and
  `down` noticeably slower than Linux
- the Apple direct reference build calls `cabal` with `--installdir=./.build` and lets cabal use
  its natural `dist-newstyle` builddir at the project root, which materializes
  `./.build/infernix`
- bootstrap `down` commands delegate to `infernix cluster down` and preserve `./.build/`,
  `./.data/`, the Apple host binary, Linux substrate images, and installed Docker or CUDA
  prerequisites
- Kind or `nvkind` create or delete uses a transient scratch kubeconfig under the execution
  context's system temp directory, then publishes the supported repo-local kubeconfig at
  `./.build/infernix.kubeconfig` on Apple or `./.data/runtime/infernix.kubeconfig` on Linux;
  stale repo-local `*.lock` files are disposable lifecycle byproducts
- container mode keeps the staged substrate file under the image-local
  `/workspace/.build/outer-container/build/` path, while cabal-home and the cabal builddir live at
  the toolchain's natural in-image locations rather than on any bind-mounted host path
- container mode runs against a baked image snapshot and bind-mounts only `./.data/` plus the
  Docker socket; no docker-managed named volumes back the outer-container build root, and the
  substrate image uses `tini` as its entrypoint for clean signal handling
- Linux Kind or `nvkind` configs use repo-local state under `./.data/`; the outer container no
  longer forwards a host-repo-root override
- on the Linux outer-container path, the baked image carries the chart archive cache at
  `/opt/infernix/chart/charts/` for Harbor, PostgreSQL, Pulsar, MinIO, and Envoy Gateway, with
  `/workspace/chart/charts` linked to that image-local cache so fresh launcher containers can
  reuse the same dependency bundle without reconstructing it from the network every time
- routed E2E on Linux runs Playwright inside the same substrate image with
  `npm --prefix web exec -- playwright test`
- when `demo_ui` is enabled, the demo surface stays cluster-resident on Apple and Linux alike
- `docker compose up` and `docker compose exec` are not supported operator workflows
- assistant-facing repository workflow rules live in [assistant_workflow.md](assistant_workflow.md)

## Cross-References

- [haskell_style.md](haskell_style.md)
- [assistant_workflow.md](assistant_workflow.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [testing_strategy.md](testing_strategy.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
