# Local Development

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Describe the supported local operator workflows for Apple host-native and
> containerized Linux execution.

## Supported Workflows

- Apple clean-host support exposes `./bootstrap/apple-silicon.sh` as the supported stage-0
  entrypoint. It reconciles Homebrew, ghcup, and fixed `/opt/homebrew/bin/jq` itself; its build path
  requires existing fixed `/opt/homebrew/bin/colima` plus a nonempty, parseable Colima profile
  inventory. It never installs Colima, creates a Colima profile or VM, or switches Docker contexts
- the Apple stage-0 bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables,
  measures physical memory and the active Colima pledge, and refuses unless at least 12288 MiB of
  effective memory remains, so its fixed one-worker 6144 MiB seed account fits the 50% toolchain
  share before the exact Cabal handoff. Haskell protobuf bindings are checked in under an exact
  hash manifest, so Darwin neither installs nor launches `protoc` or a Haskell generator plugin
  during an ordinary build or lint run
- after `./.build/infernix` exists on Apple Silicon, supported host-native commands may reconcile
  Homebrew-managed `kind`, `kubectl`, `helm`, Node.js, the Homebrew-managed `python@3.12` formula
  and `python3.12` command, and Poetry through the supported package-manager or user-local
  bootstrap path when the active flow first needs them. They must not use cross-architecture
  emulation or provision a Docker VM or context
- `linux-cpu` and `linux-gpu` expose repo-owned `bootstrap/*.sh` entrypoints that keep host
  prerequisites probe-driven and idempotent; the CPU path stops at Docker Engine plus the Docker
  buildx and Compose plugins, and the GPU path adds only the supported NVIDIA driver and
  container-toolkit setup
- hardware-specific validation runs on the machine that owns the accelerator; a cross-hardware
  claim requires both Apple Silicon and CUDA Linux gates against the same source fingerprint
- the target bootstrap responsibility boundary keeps shell scripts out of Kind, Kubernetes
  manifests, and cluster workload image-pull orchestration: after prerequisites and the
  substrate-specific launcher are available, lifecycle commands are ordinary `infernix` binary
  invocations
- the lifecycle keeps Kind and `nvkind` lock-taking off repo-visible paths by using a transient
  scratch kubeconfig under the execution context's system temp directory during cluster create or
  delete, then publishing the durable repo-local kubeconfig afterward

## Apple Host-Native Flow

```bash
./bootstrap/apple-silicon.sh build
./bootstrap/apple-silicon.sh up
./bootstrap/apple-silicon.sh status
./bootstrap/apple-silicon.sh down
```

The operator/demo cluster must be down before the separate harness workflow:

```bash
./bootstrap/apple-silicon.sh test
```

Post-build operator/demo path (use the bootstrap again for every rebuild):

```bash
./bootstrap/apple-silicon.sh build
./.build/infernix init
./.build/infernix cluster up
./.build/infernix cluster status
./.build/infernix cluster down
```

Post-build harness path, after the operator cluster is down:

```bash
./.build/infernix init --runtime-mode apple-silicon --demo-ui true --if-missing
./.build/infernix test init --runtime-mode apple-silicon --demo-ui true
./.build/infernix test all
```

The bootstrap `test` command runs the governed `init --if-missing` and Apple test initialization
before `test all`, so it works in a clean workspace without a separate config step. It preserves an
existing operator config, performs no operator `cluster up`, and refuses a live `OperatorOwned`
cluster because the harness owns its own cluster lifecycle.

The first supported Apple host-native command that needs Docker, Kubernetes tooling, Node.js,
Python, or Poetry reconciles those prerequisites automatically.

### Config Is Created by Explicit `init`

The `infernix` binary is the sole generator of every `.dhall`, and none is version-controlled.
Create config explicitly:

- `infernix init` writes the operator runtime config `./infernix.dhall`, the host manifest
  `./infernix-host.dhall`, and the host worker secrets under `./.data/runtime/secrets/`. It fails
  fast if `./infernix.dhall` already exists unless `--force`.
- `infernix test init` writes the thin `./infernix.test.dhall` that the test harness reads.

There is no hidden auto-generate-if-absent backstop inside ordinary `infernix` commands: every
runtime, cluster, cache, and aggregate `infernix test …` command fails fast naming the exact init to
run when its config is missing (focused `infernix lint …` and `infernix docs check` remain
config-independent). Help and `infernix init` are also config-independent by necessity: init derives
its paths without decoding an existing host manifest and writes through the closed runtime-config
authority, so `init --force` can replace a stale schema while ordinary commands remain fail-closed.
`./bootstrap/apple-silicon.sh up` is a stage-0 convenience exception: it explicitly runs
`./.build/infernix init --if-missing` before `cluster up`. The test harness has a corresponding
explicit wrapper: `./bootstrap/apple-silicon.sh test` runs
`./.build/infernix init --runtime-mode apple-silicon --demo-ui true --if-missing`, then
`./.build/infernix test init --runtime-mode apple-silicon --demo-ui true`, before `test all`. It then
owns `./infernix.dhall` for the duration of the run: `infernix test integration|e2e|all` reads
`./infernix.test.dhall` (fail fast → `infernix test init`), backs up any existing `./infernix.dhall`,
generates the harness config from the test config, runs the suites, and restores the backup (or
removes the generated file when there was none). That backup is held at
`./infernix.dhall.harness-backup` and reconciled on entry, so a killed run cannot leave your
`./infernix.dhall` clobbered by the test config (canonical home
[Configuration Doctrine](../architecture/configuration_doctrine.md)), while the owner-atomic
reservation and teardown are owner-atomic over the all-Haskell lifecycle-lock and supervision
boundary; canonical home
[Configuration Doctrine](../architecture/configuration_doctrine.md)). The Linux
launcher image bakes both files at build time so the containerized `infernix test all` runs without a
manual init step.

## Containerized Linux Flow

```bash
./bootstrap/linux-cpu.sh up
./bootstrap/linux-cpu.sh status
./bootstrap/linux-cpu.sh down
./bootstrap/linux-cpu.sh test
```

Direct reference path:

```bash
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster up
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster status
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster down
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all
```

The final command is a separate harness-owned workflow and requires the operator cluster to be
down. It is not a validation step against the preceding `cluster up`.

For `linux-gpu`, use `./bootstrap/linux-gpu.sh ...` as the supported entrypoint. The underlying
reference path uses the same `compose.yaml` service and prefixes the direct command with
`LAUNCHER_IMAGE=infernix-linux-gpu:local`. If the host does not already pass `nvidia-smi -L`, the
supported bootstrap installs the recommended Ubuntu compute driver, stops, and instructs the
operator to reboot before rerunning the same command.

## Cross-Hardware Validation

Machine-independent gates may run on either supported host; accelerator claims require their owning
hardware lane.

The machine-independent gate set — `infernix test lint`, `infernix test unit`,
`infernix lint files/docs/chart/proto`, `infernix docs check`, the web unit suite, and
`poetry run check-code` — runs on whichever machine is present, and has two declared prerequisites.
`infernix test unit` owns the exact closed Cabal vectors for compile-fail, artifact transaction,
Apple materializer, capped observer, execution-plan, and unit; no focused suite needs a bare host
Cabal instruction. First, `infernix init` must have written the repo-root
`./infernix-host.dhall` host manifest. Second, the toolchain runs under a declared memory ceiling
([bounded_host_memory.md](../architecture/bounded_host_memory.md)): `cabal build all` is the largest
consumer among the images that ceiling covers, and the gate asserts that a ceiling exists, that the
host was observed able to fund it, and that no competing toolchain claimant was present — not that
no exhaustion occurred. The browser, the web and Python images, and the inference daemon are outside
that ceiling and are host-reserve claimants.

The two prerequisites are the same command. `infernix init` measures this host's memory into the
manifest and then derives the per-machine ceiling into the untracked repo-root
`cabal.project.local`, which states its job count and compiler heap/address settings. The derived
plan separately carries the fixed 1024 MiB control/helper cap and accounts
`jobs × compilerHeap + (jobs + 1) × controlHeap`: the live Cabal driver plus one helper/native
auxiliary slot per worker. On Darwin the effective measurement subtracts the conservatively observed
active Colima pledge from physical RAM; an unavailable or malformed fixed-path observation refuses
initialization instead of assuming a zero pledge. A clean clone has no binary capable of that typed
observation, so `./bootstrap/apple-silicon.sh build` performs its narrow fixed-path stage-0
measurement and uses an exact one-worker 4096 MiB compiler plus two 1024 MiB control claims; it does
not pretend initialization occurred. Commands such as `up` subsequently run `infernix init`, while
standalone `build` remains only a seed-bound rebuild. Regenerate rather than edit the generated file
— a hand-edited job count divided from nothing is the failure the doctrine exists for.

For an 8192 MiB account the derived one-worker plan uses a 6144 MiB compiler heap, not a fixed
4096 MiB heap: after reserving `(jobs + 1) × 1024 MiB` for the driver/helper claims, the mint assigns
the remaining account to the compiler slot. The 4096 MiB value is a measured floor; the derived cap
is the largest residual share the admitted job count can use without exceeding the account, not an
estimate of expected consumption.

After running `infernix init`, the opt-in `infernix internal
validate-darwin-build-memory` command is the closed Apple-host evidence surface for that unenforced
lane. It refuses anywhere but Darwin, resolves the live
`DarwinHeapCapMechanism`, re-observes the exact generated `jobs`, `-M`, and `-xr` triple, and passes
the authority-derived 1024 MiB Cabal/control cap plus compiler job count, heap, and reservation
directly to fresh `cabal build all --enable-tests` and `cabal install ... all:exes` invocations in an
internally created scratch build root. It samples
each owned process group at a fixed cadence through the fixed Apple observer and reports the
**sampled peak aggregate physical footprint**, together with physical/effective memory, the active
Colima pledge, the plan product and its fixed-point multiple over the sampled maximum, sample
counts, durations, and exit statuses. The build must contain a positive footprint sample; a reused
install that reaches proven terminal completion before the first one-second probe is reported
explicitly as `terminal-before-first-fixed-cadence-probe`, never assigned a fabricated sample.
Observer loss fails
closed, and ordinary as well as exceptional completion must prove the group has no descendants
before releasing it. This is sampled evidence, not an enforced aggregate ceiling: a fixed cadence
can miss a transient peak, and the command makes no claim about processes it did not start. The
private scratch build root and its installed executables are removed when the command finishes or
fails; the evidence printed to the caller is the retained artifact. The shipped operator CLI parent
and its fixed observer tools remain in the non-toolchain host reserve and outside both the Cabal
process group and reported account.

The two Darwin-only Apple materializer validation modes have fixed authority-owned CLI surfaces:
`infernix internal validate-darwin-audiveris-cancellation` and
`infernix internal validate-darwin-installed-python-source-isolation`. They select exact test-option
vectors internally; callers cannot supply a Cabal target or arbitrary test options.

- Apple-specific claims use the Apple host-native bootstrap and direct `./.build/infernix` commands.
- Linux/CUDA, chart, and outer-container claims use the `linux-gpu` bootstrap and
  `docker compose run --rm infernix infernix ...` reference path.
- `linux-cpu` is a portable CPU-only lane for native Linux amd64 and native Linux arm64. On an
  Apple Silicon host it runs through the operator's already-running native arm64 Docker daemon, the
  Colima Linux VM, so the launcher container is scheduled on that VM's native `linux/arm64` kernel
  rather than under emulation; `./bootstrap/linux-cpu.sh` resolves the Homebrew Docker CLI and
  drives the lane through the existing daemon without creating or switching a context or
  provisioning a VM. It is never exercised through cross-architecture emulation and does not
  replace CUDA Linux for GPU-sensitive claims.
- Full cross-hardware evidence requires the Apple Silicon and CUDA Linux full-suite gates against
  the same source fingerprint.

## Engine Adapter Testing

When exercising a Python-native engine adapter, Poetry materializes a local environment only for
the shared adapter project:

```bash
./.build/infernix test unit
```

## Rules

- the active substrate comes from repo-root `./infernix.dhall` rather than a CLI flag
- supported config creation is explicit and binary-owned: `infernix init` creates operator runtime
  config and `infernix test init` creates the test-harness input; ordinary lifecycle and validation
  commands validate those files and fail fast naming the required init when one is absent
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
- repository-owned native implementation source is forbidden: do not add
  C/C++/Objective-C/CUDA/assembly/Metal/Swift/C2HS/HSC/C-- sources or headers, Cabal native-source fields or
  native-token CPP definitions, or embedded native source/writers/compiler invocations in another
  implementation language. `infernix lint files` enforces this boundary; native implementation
  inside upstream packages remains allowed
- on Linux, routed E2E runs Playwright inside the substrate image on Docker's private `kind`
  network against the Kind control-plane DNS instead of `host.docker.internal`; Apple host-native
  routed E2E uses host `npm exec` with the same typed fixture and must pass the Apple host-native
  gate
- on Apple, retained Kind state under `./.data/kind/apple-silicon/` is replayed into and out of
  the worker instead of being bind-mounted, so large retained state can make `up`, `test`, and
  `down` noticeably slower than Linux
- the Apple direct reference build calls `cabal` with `--installdir=./.build` and lets cabal use
  its natural `dist-newstyle` builddir at the project root, which materializes
  `./.build/infernix`. It runs under the declared build ceiling
  ([bounded_host_memory.md](../architecture/bounded_host_memory.md)); on the Apple lane that ceiling
  is a runtime heap cap plus a bounded job count, because Darwin provides neither cgroups nor an
  enforced address-space limit
- bootstrap `down` commands delegate to `infernix cluster down` and preserve `./.build/`,
  `./.data/`, the Apple host binary, Linux substrate images, and installed Docker or CUDA
  prerequisites
- Kind or `nvkind` create or delete uses a transient scratch kubeconfig under the execution
  context's system temp directory, then publishes the supported repo-local kubeconfig at
  `./.build/infernix.kubeconfig` on Apple or `./.data/runtime/infernix.kubeconfig` on Linux;
  stale repo-local `*.lock` files are disposable lifecycle byproducts
- container mode keeps build artifacts under the image-local
  `/workspace/.build/outer-container/build/` path and uses binary-generated image defaults; the
  operator runtime-config authority remains repo-root `./infernix.dhall`, while cabal-home and the
  cabal builddir live at the toolchain's natural in-image locations rather than on any
  bind-mounted host path
- container mode runs against a baked image snapshot and bind-mounts only `./.data/` plus the
  Docker socket; no docker-managed named volumes back the outer-container build root, and the
  substrate image uses `tini` as its entrypoint for clean signal handling
- Linux Kind or `nvkind` configs use repo-local state under `./.data/`; the outer container no
  longer forwards a host-repo-root override
- on the Linux outer-container path, the baked image carries the chart archive cache at
  `/opt/infernix/chart/charts/` for PostgreSQL, Pulsar, MinIO, and Envoy Gateway, with
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
