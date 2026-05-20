# Build Artifacts

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define where generated artifacts live and keep them out of tracked source paths.

## TL;DR

- Host-native builds write repo-local outputs under `./.build/`; supported outer-container flows
  also write under `./.build/outer-container/` on the host through a `./.build:/workspace/.build`
  bind mount, plus durable repo-local state under `./.data/`.
- Generated frontend contracts live only under `web/src/Generated/`, and generated browser bundles
  live under `web/dist/`.
- Runtime inference results reload only from protobuf-backed `./.data/runtime/results/*.pb`
  records; retired `*.state` files are not part of the supported artifact contract.

## Current Status

The current worktree follows the supported artifact layout directly: the host path stages
`./.build/infernix` and `./.build/infernix-demo`, the Linux substrate images own
`/usr/local/bin/infernix*` while outer-container build state lives under
`./.build/outer-container/` on the host through the `./.build:/workspace/.build` bind mount,
generated frontend contracts stay under `web/src/Generated/`, and runtime result or
cache-manifest state uses protobuf-backed `*.pb` files instead of legacy text-state fallbacks.
Kind and `nvkind` cluster create or delete uses transient scratch kubeconfig state under the
execution context's temp directory, and only the published repo-local kubeconfig paths are part
of the supported artifact contract.

## Build Roots

- the repo-local operator binaries live at `./.build/infernix` and `./.build/infernix-demo`
- the supported Apple host bootstrap ultimately calls
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`,
  which lets cabal use its natural `dist-newstyle` builddir at the project root while installing
  the launcher binaries under `./.build/`
- on the supported outer-container path, cabal-home and the cabal builddir live at the toolchain's
  natural in-image locations (`/root/.cabal/`, `dist-newstyle/`); they are not bind-mounted to the
  host, and `${INFERNIX_BUILD_ROOT}=/workspace/.build/outer-container/build` only carries the
  staged substrate file
- on the outer-container path, the baked launcher binaries remain `/usr/local/bin/infernix` and
  `/usr/local/bin/infernix-demo`; the substrate image uses `tini` as its `ENTRYPOINT` for clean
  signal handling and zombie reaping
- the substrate image captures the sorted source snapshot at
  `/opt/infernix/source-snapshot-files.txt`, which sits outside the bind-mounted `./.build/` tree
  so it stays in the image overlay where git-less `infernix lint files` runs can read it
- `cluster up` publishes `./.build/infernix.kubeconfig` on the host path after Kind create or
  delete uses a transient host-local scratch kubeconfig
- `cluster up` publishes `./.data/runtime/infernix.kubeconfig` on the outer-container path after
  Kind or `nvkind` create or delete uses a transient launcher-local scratch kubeconfig under the
  container temp directory
- the active generated substrate file lives at `./.build/infernix-substrate.dhall` on the Apple
  host path and `./.build/outer-container/build/infernix-substrate.dhall` on the host for the
  Linux outer-container path, where it is visible inside the launcher container as
  `/workspace/.build/outer-container/build/infernix-substrate.dhall`
- `cluster up` writes `./.data/runtime/publication.json` as the publication inventory consumed by
  routed status surfaces
- the web build stages `web/src/Generated/Contracts.purs`, written by
  `infernix internal generate-purs-contracts`
- `spago bundle --module Main --outfile dist/app.js --platform browser --bundle-type app`
  produces the static demo bundle in `web/dist/`
- inference-result reloads use `./.data/runtime/results/*.pb`
- cache durability manifests use `./.data/object-store/manifests/<runtime-mode>/<model-id>/default.pb`
- `ensurePoetryProjectReady` regenerates Python protobuf stubs under `tools/generated_proto/` when
  they are missing

## Generated Demo Config Publication

The substrate file is a typed Dhall record at `infernix-substrate.dhall`; the schema is defined at
`dhall/InfernixSubstrate.dhall` and decoded in-process by the `dhall` Haskell library. Cluster pods
that consume the file link the same library through the in-cluster `infernix` binary.

- Apple host lifecycle and validation flows materialize or verify `infernix-substrate.dhall`
  under `./.build/`; `./.build/infernix internal materialize-substrate apple-silicon` remains the
  direct helper for explicit restaging or inspection
- Linux outer-container lifecycle and validation flows materialize or verify
  `./.build/outer-container/build/infernix-substrate.dhall` on the host through the bind-mounted
  build tree; `docker compose run --rm infernix infernix internal materialize-substrate <substrate> --demo-ui <true|false>`
  remains the direct helper for explicit restaging or inspection
- `cluster up` mirrors the cluster-role substrate payload under
  `./.data/runtime/configmaps/infernix-demo-config/` and publishes it into
  `ConfigMap/infernix-demo-config` on the real cluster path; on Apple this cluster-role payload is
  rendered from the active staged substrate metadata and `demo_ui` setting rather than copied
  verbatim from the host-role file under `./.build/`
- in cluster-resident execution contexts, the ConfigMap-backed file is mounted beside the binary
- the cluster pod's ConfigMap-backed mount path is `/opt/build/infernix-substrate.dhall`

## Rules

- repo-owned shell is limited to the `bootstrap/*.sh` stage-0 host bootstrap entrypoints; build
  and launcher ownership stays with the direct `cabal`, `docker compose`, and `infernix`
  surfaces, and shell lifecycle commands preserve `./.build/`, `./.data/`, host-level container
  builds, Apple host binaries, and installed Docker or CUDA prerequisites
- generated demo-config files live under the active build root, not tracked source paths
- `cluster up`, `service`, and the validation entrypoints own the generated substrate-file
  preflight for their execution context: they materialize or validate the file under the active
  build root before relying on it, while the explicit internal materialization helper remains
  available for direct operator restaging
- kubeconfig output is repo-local and execution-context-specific: Apple host mode publishes
  `./.build/infernix.kubeconfig`, while Linux outer-container mode publishes the durable
  `./.data/runtime/infernix.kubeconfig`; Kind and `nvkind` cluster create or delete uses a
  transient scratch kubeconfig outside the repo tree and may clean stale repo-local `*.lock`
  artifacts automatically
- `infernix lint files` uses tracked files from `.git` when VCS metadata is present and otherwise
  uses `/opt/infernix/source-snapshot-files.txt` baked into the substrate image on git-less Linux
  image runs
- publication state lives under `./.data/runtime/` and is regenerated by `cluster up`,
  `cluster down`, or publication-surface refresh
- generated PureScript contract modules stage under `web/src/Generated/` and the `spago bundle`
  output lives in `web/dist/`
- runtime result and cache-manifest reload paths are protobuf-backed `*.pb` files only; supported
  flows do not read legacy `*.state` compatibility files
- generated web build output lives under `web/dist/`; Playwright validation artifacts use
  Playwright default output directories such as `test-results/` and `playwright-report/` under the
  active runner working tree when emitted, and compose-run artifacts are container-local unless
  explicitly bind-mounted
- engine-adapter Python builds use Poetry against the shared `python/` project; outside the
  cluster, `poetry install --directory python` materializes a repo-local adapter virtual
  environment at `python/.venv/`, and Linux substrate image builds run the same shared install
- the supported web build runs on Node.js 22.5+ on both the host and Linux substrate-image paths
- `.gitignore` and `.dockerignore` mirror the generated-artifact ignore set: Poetry lockfiles,
  generated protobuf stubs, Python bytecode, mypy and ruff caches, `web/spago.lock`,
  `web/package-lock.json`, `web/src/Generated/`, `web/dist/`, `web/output/`, and
  `python/.venv/` are not tracked

## Validation

- `infernix docs check` fails if this governed artifact document loses its required structure or
  metadata contract.
- `infernix test unit` covers protobuf-backed result reloads, protobuf-backed cache-manifest
  handling, and PureScript contract generation to `web/src/Generated/Contracts.purs`.
- `infernix lint files` fails if the implemented tracked generated-source set returns to tracked
  paths, including generated protobuf stubs, generated PureScript contracts, Python bytecode,
  Poetry or Spago lockfiles, and mypy or ruff cache directories.
- `git ls-files` remains the direct audit surface for ignored derived outputs such as
  `web/package-lock.json`, `web/dist/`, `web/output/`, and `python/.venv/`.

## Cross-References

- [docker_policy.md](docker_policy.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
