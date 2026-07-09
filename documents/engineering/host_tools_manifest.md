# Host Tools Manifest

**Status**: Authoritative source
**Referenced by**: [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md), [../development/no_env_vars.md](../development/no_env_vars.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define the host-manifest record (reflected from the `Infernix.HostConfig` decoder
> type; printed by `infernix internal dhall-schema host`), the absolute-path discipline for every
> external command the project invokes, and the per-tool field mapping the Haskell + bootstrap-shell
> codepaths consult.

## TL;DR

- The generated host manifest `./infernix-host.dhall` (written by `infernix init`) is the single
  authoritative inventory of every external command the project ever invokes — by absolute path. Its
  schema is reflected from the `HostConfig` Haskell type; no `.dhall` is version-controlled.
- The Haskell binary loads this file at startup via the `dhall` library and threads a
  `HostConfig` record through every entry point. Every `proc`/`callProcess`/`readProcess`
  invocation reads its command path from `HostConfig.toolPaths.*`.
- Bootstrap shell scripts use the same paths — either as hardcoded constants written into the
  script (for the small set of commands that run before the launcher binary exists) or by
  delegating to the binary after it does.
- No code path resolves a command name through the operator's shell search path. The
  Haskell-style lint gate rejects both `proc "<bare-name>"` and direct
  `findExecutable` / `findExecutables` discovery for manifest-owned host tools.

## Schema

```dhall
let HostTool = Text

let ToolPaths =
      { docker : HostTool
      , kubectl : HostTool
      , helm : HostTool
      , kind : HostTool
      , cabal : HostTool
      , ghc : HostTool
      , ghcup : HostTool
      , ormolu : HostTool
      , hlint : HostTool
      , npm : HostTool
      , node : HostTool
      , python3 : HostTool
      , poetry : HostTool
      , protoc : HostTool
      , git : HostTool
      , tar : HostTool
      , curl : HostTool
      , aptGet : HostTool
      , brew : HostTool
      , sudo : HostTool
      , systemctl : HostTool
      , mkdir : HostTool
      , chmod : HostTool
      , ln : HostTool
      , install : HostTool
      , id : HostTool
      , getent : HostTool
      , cut : HostTool
      , dirname : HostTool
      , bash : HostTool
      , crictl : HostTool
      , chown : HostTool
      , nvidiaSmi : HostTool
      , nvkind : HostTool
      , skopeo : HostTool
      , hostname : HostTool
      }

let FilesystemConventions =
      { repoRoot : Text
      , buildRoot : Text
      , dataRoot : Text
      , runtimeRoot : Text
      , kubeconfigPath : Text
      , secretsRoot : Text
      , homeDirectory : Text
      , kindRoot : Text
      }

let HostExecutionContext =
      < AppleHostNative
      | LinuxOuterContainer
      >

in    { hostExecutionContext : HostExecutionContext
      , hostArchitecture : Text
      , toolPaths : ToolPaths
      , filesystem : FilesystemConventions
      , playwrightHost : Text
      , controlPlaneContext : Text
      }
```

The schema is reflected from the `HostConfig` decoder type (`infernix internal dhall-schema host`);
the operator's generated manifest is written by `infernix init` to `./infernix-host.dhall`
(gitignored). There is no packaged `.dhall` schema in the repo or launcher image. `hostArchitecture`
stores the normalized native host architecture (`amd64` or `arm64`) used by the `linux-cpu`
publication selector.

## Per-tool field mapping

| Tool | Field | Apple default | Linux launcher default |
|------|-------|---------------|------------------------|
| docker | `toolPaths.docker` | `/opt/homebrew/bin/docker` (current native arm64 Docker context required) | `/usr/bin/docker` |
| kubectl | `toolPaths.kubectl` | `/opt/homebrew/bin/kubectl` | `/usr/local/bin/kubectl` (baked into image) |
| helm | `toolPaths.helm` | `/opt/homebrew/bin/helm` | `/usr/local/bin/helm` |
| kind | `toolPaths.kind` | `/opt/homebrew/bin/kind` | `/usr/local/bin/kind` |
| cabal | `toolPaths.cabal` | `${HOME}/.ghcup/bin/cabal` | baked: `/root/.ghcup/bin/cabal` |
| ghc | `toolPaths.ghc` | `${HOME}/.ghcup/bin/ghc` | baked: `/root/.ghcup/bin/ghc` |
| ghcup | `toolPaths.ghcup` | `${HOME}/.ghcup/bin/ghcup` | (unused; image already has ghc/cabal) |
| ormolu | `toolPaths.ormolu` | `./.build/haskell-style-tools/bin/ormolu` | same |
| hlint | `toolPaths.hlint` | `./.build/haskell-style-tools/bin/hlint` | same |
| npm | `toolPaths.npm` | `/opt/homebrew/bin/npm` | baked: `/usr/local/bin/npm` |
| node | `toolPaths.node` | `/opt/homebrew/bin/node` | baked: `/usr/local/bin/node` |
| python3 | `toolPaths.python3` | `/opt/homebrew/bin/python3.12` | `/usr/bin/python3` |
| poetry | `toolPaths.poetry` | `${HOME}/.local/bin/poetry` | baked: `/opt/poetry/bin/poetry`; manifestless fallback checks fixed `/opt/poetry/bin/poetry`, `/usr/local/bin/poetry`, `/usr/bin/poetry` only |
| protoc | `toolPaths.protoc` | `/opt/homebrew/bin/protoc` | `/usr/bin/protoc` |
| git | `toolPaths.git` | `/usr/bin/git` | `/usr/bin/git` |
| tar | `toolPaths.tar` | `/usr/bin/tar` | `/usr/bin/tar` |
| curl | `toolPaths.curl` | `/usr/bin/curl` | `/usr/bin/curl` |
| apt-get | `toolPaths.aptGet` | n/a (macOS) | `/usr/bin/apt-get` |
| brew | `toolPaths.brew` | `/opt/homebrew/bin/brew` | n/a |
| sudo | `toolPaths.sudo` | `/usr/bin/sudo` | `/usr/bin/sudo` |
| systemctl | `toolPaths.systemctl` | n/a | `/usr/bin/systemctl` |
| crictl | `toolPaths.crictl` | n/a | `/usr/local/bin/crictl` |
| chown | `toolPaths.chown` | `/usr/sbin/chown` | `/usr/bin/chown` |
| nvidia-smi | `toolPaths.nvidiaSmi` | n/a | `/usr/bin/nvidia-smi` |
| nvkind | `toolPaths.nvkind` | n/a | `/usr/local/bin/nvkind` |
| skopeo | `toolPaths.skopeo` | `/opt/homebrew/bin/skopeo` | `/usr/bin/skopeo` |
| hostname | `toolPaths.hostname` | `/bin/hostname` | `/usr/bin/hostname` |

The former `tart` field (Haskell record selector `hostTart`) is no longer part of the current
schema. Phase 1 Sprint 1.14 removed `HostTool.HostTart`, the `AppleTart` prerequisite, and the
Tart-backed command helpers; `infernix internal materialize-metal-engines` now materializes typed
engine-artifact manifests through the headless host lane described in
[apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md). The cleanup
receipt is recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

The Apple defaults assume Homebrew (`/opt/homebrew/bin`) and ghcup. Docker-backed Apple work
requires the current Docker context to already point at a native arm64 Docker daemon; Infernix must
not create or switch Docker contexts, create a Colima VM, or use emulation. The Linux launcher
defaults are baked into the launcher image at build time and updated only by rebuilding the image.
Apple operators can override individual paths by editing `./.build/infernix-host.dhall`; the
resulting file is consumed on next `infernix <command>` invocation.

**Current audit note**: Phase 6 Sprint 6.34 reconciled the remaining manifest drift. Linux
`cabal`/`ghc` defaults and manifestless fallback candidates include `/root/.ghcup/bin/{cabal,ghc}`,
matching the launcher image, and the bootstrap pre-binary command inventory below reflects the current
entrypoints.

## Bootstrap shell convention

Bootstrap scripts handle the small set of commands that run *before* the launcher binary exists.
They use hardcoded absolute-path constants written into the script:

```bash
#!/usr/bin/env bash
PATH=/usr/bin:/bin                                   # neutralize ambient env
set -euo pipefail

REPO_ROOT="$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.."
HOME_DIR="$(/usr/bin/getent passwd "$(/usr/bin/id -u)" | /usr/bin/cut -d: -f6)"

readonly APT_GET=/usr/bin/apt-get
readonly SUDO=/usr/bin/sudo
readonly DOCKER=/usr/bin/docker
readonly GHCUP="${HOME_DIR}/.ghcup/bin/ghcup"
readonly CABAL="${HOME_DIR}/.ghcup/bin/cabal"

# Linux: build launcher, then delegate
"${SUDO}" "${APT_GET}" install -y docker-ce docker-compose-plugin
"${DOCKER}" compose --file "${REPO_ROOT}/compose.yaml" build infernix
"${DOCKER}" compose --file "${REPO_ROOT}/compose.yaml" run --rm infernix infernix cluster up

# Apple: build host-native binary, then delegate
"${GHCUP}" install ghc 9.12.4
"${CABAL}" install
"${REPO_ROOT}/.build/infernix" cluster up
```

The supported pre-binary command set is limited to the hardcoded constants or derived absolute paths in
`bootstrap/*.sh`: `apt-get`, `bash`, `brew`, `cabal`, `chmod`, `cmp`, `cp`, `curl`, `dirname`,
`docker`, `dpkg`, `dscl`, `env`, `getent`, `ghc`, `ghcup`, `gpg`, `grep`, `id`, `install`, `mktemp`,
`nvidia-ctk`, `nvidia-smi`, `protoc`, `rm`, `sed`, `skopeo`, `sudo`, `systemctl`, `tr`,
`ubuntu-drivers`, `uname`, and `usermod`. Everything else should flow through the launcher binary,
which reads its tool paths and native host architecture from `HostConfig`. None of these names may
become inherited environment overrides or ambient `PATH` lookups.

## Adding a new external command

When a sprint introduces a new external CLI:

1. Add a field to the `ToolPaths` record in the `HostConfig` Haskell decoder type
   (`src/Infernix/HostConfig.hs`); the reflected schema and `infernix init` defaults pick it up
   automatically — there is no `.dhall` schema file to edit.
2. Update the materialization helper in `src/Infernix/CLI.hs` to seed the field with the
   supported default for each execution context.
3. Use `runHostTool hostConfig <toolName> args` (helper in `src/Infernix/HostTools.hs`) at the
   call site. Never write `proc "<bare-name>"` directly or call `findExecutable` /
   `findExecutables` to discover a manifest-owned tool.
4. Document the field + supported defaults in this manifest doc (the per-tool table above).
5. The Haskell-style lint gate (`forbiddenBareProcCommands`, derived from the `HostTools.HostTool`
   enum via `hostToolCommandNames`) picks up the new command automatically — adding the `HostTool`
   constructor extends the gate, so it cannot drift from the registered tool set.

## Validation

- `cabal build all` — every decoder field must exist in the schema.
- `infernix test lint` — the Haskell-style lint gate rejects any `proc "<bare-name>"` whose name
  matches a `ToolPaths` field, and rejects `findExecutable` / `findExecutables` outside the lint
  module's own token list. Adding a new command without adding the schema field first fails this
  check.
- `grep -rEn '\bproc "(docker|kubectl|helm|kind|cabal|ghc|ghcup|npm|node|python3|poetry|protoc|git|tar|curl|apt-get|brew|skopeo|sudo|systemctl)"' src/ test/` returns zero matches, and
  `rg -n 'findExecutable|findExecutables' Setup.hs src test` returns only the lint module's forbidden-token
  list.

## Cross-References

- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md) — overall
  configuration substrate.
- [apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md) — Tart-free
  Apple Metal/Core ML materialization target.
- [../development/no_env_vars.md](../development/no_env_vars.md) — developer-facing rules.
- [cluster_config_manifest.md](cluster_config_manifest.md) — the matching cluster-wiring manifest.
