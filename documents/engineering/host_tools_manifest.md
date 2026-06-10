# Host Tools Manifest

**Status**: Authoritative source
**Referenced by**: [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md), [../development/no_env_vars.md](../development/no_env_vars.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define the `dhall/InfernixHost.dhall` schema, the absolute-path discipline for every
> external command the project invokes, and the per-tool field mapping the Haskell + bootstrap-shell
> codepaths consult.

## TL;DR

- `dhall/InfernixHost.dhall` is the single authoritative inventory of every external command the
  project ever invokes — by absolute path.
- The Haskell binary loads this file at startup via the `dhall` library and threads a
  `HostConfig` record through every entry point. Every `proc`/`callProcess`/`readProcess`
  invocation reads its command path from `HostConfig.toolPaths.*`.
- Bootstrap shell scripts use the same paths — either as hardcoded constants written into the
  script (for the small set of commands that run before the launcher binary exists) or by
  delegating to the binary after it does.
- No code path resolves a command name through the operator's shell search path. The
  Haskell-style lint gate rejects `proc "<bare-name>"` for every command listed in the manifest.

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
      , hostTart : HostTool
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

The schema itself lives in `dhall/InfernixHost.dhall`; the materialized operator copy lives in
`./.build/infernix-host.dhall` (Apple) or in the launcher image at
`/opt/infernix/dhall/InfernixHost.dhall` (Linux). `hostArchitecture` stores the normalized native
host architecture (`amd64` or `arm64`) used by the `linux-cpu` publication selector.

## Per-tool field mapping

| Tool | Field | Apple default | Linux launcher default |
|------|-------|---------------|------------------------|
| docker | `toolPaths.docker` | `/opt/homebrew/bin/docker` (current native arm64 Docker context required) | `/usr/bin/docker` |
| kubectl | `toolPaths.kubectl` | `/opt/homebrew/bin/kubectl` | `/usr/local/bin/kubectl` (baked into image) |
| helm | `toolPaths.helm` | `/opt/homebrew/bin/helm` | `/usr/local/bin/helm` |
| kind | `toolPaths.kind` | `/opt/homebrew/bin/kind` | `/usr/local/bin/kind` |
| cabal | `toolPaths.cabal` | `${HOME}/.ghcup/bin/cabal` | baked: `/usr/local/bin/cabal` |
| ghc | `toolPaths.ghc` | `${HOME}/.ghcup/bin/ghc` | baked: `/usr/local/bin/ghc` |
| ghcup | `toolPaths.ghcup` | `${HOME}/.ghcup/bin/ghcup` | (unused; image already has ghc/cabal) |
| ormolu | `toolPaths.ormolu` | `./.build/haskell-style-tools/bin/ormolu` | same |
| hlint | `toolPaths.hlint` | `./.build/haskell-style-tools/bin/hlint` | same |
| npm | `toolPaths.npm` | `/opt/homebrew/bin/npm` | baked: `/usr/local/bin/npm` |
| node | `toolPaths.node` | `/opt/homebrew/bin/node` | baked: `/usr/local/bin/node` |
| python3 | `toolPaths.python3` | `/opt/homebrew/bin/python3.12` | `/usr/bin/python3` |
| poetry | `toolPaths.poetry` | `${HOME}/.local/bin/poetry` | baked: `/opt/poetry/bin/poetry` |
| protoc | `toolPaths.protoc` | `/opt/homebrew/bin/protoc` | `/usr/bin/protoc` |
| git | `toolPaths.git` | `/opt/homebrew/bin/git` | `/usr/bin/git` |
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
| skopeo | `toolPaths.skopeo` | n/a | `/usr/bin/skopeo` |
| hostname | `toolPaths.hostname` | `/bin/hostname` | `/usr/bin/hostname` |
| tart | `toolPaths.hostTart` | `/opt/homebrew/bin/tart` | n/a |

`hostTart` is the absolute path to `tart` on Apple Silicon — `/opt/homebrew/bin/tart`. Its purpose
is to drive the headless `tart` macOS VM that builds the Metal and Core ML native engine artifacts.
The field is added per the field-first rule: `tart` is recorded in `dhall/InfernixHost.dhall`
before any invocation site reads it, so the lint gate recognizes the name and rejects any
`proc "tart"` bare-name call. tart is native arm64 macOS virtualization, reconciled through
Homebrew (`brew install tart`); it is not a Docker or Colima lane and provisions no Docker context
or Colima VM. The headless `tart` guest runs Xcode-only Metal and Core ML engine builds and copies
the resulting artifacts to `./.data/engines/<adapterId>/`; the host then runs them against Metal.
See the "Tart Metal-Engine Build Lane" section of
[../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md) and the
engine-build sub-record in
[../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md).

The Apple defaults assume Homebrew (`/opt/homebrew/bin`) and ghcup. Docker-backed Apple work
requires the current Docker context to already point at a native arm64 Docker daemon; Infernix must
not create or switch Docker contexts, create a Colima VM, or use emulation. The Linux launcher
defaults are baked into the launcher image at build time and updated only by rebuilding the image.
Apple operators can override individual paths by editing `./.build/infernix-host.dhall`; the
resulting file is consumed on next `infernix <command>` invocation.

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

The pre-binary command set is intentionally tiny: `apt-get`, `sudo`, `docker`, `ghcup`, `cabal`,
`brew`, `bash`, `dirname`, `getent`, `id`, `cut`. Everything else flows through the launcher
binary, which reads its tool paths and native host architecture from `HostConfig`.

## Adding a new external command

When a sprint introduces a new external CLI:

1. Add a field to the `ToolPaths` record in `dhall/InfernixHost.dhall` (and to the matching
   Haskell decoder in `src/Infernix/Substrate.hs`'s `HostConfig` record).
2. Update the materialization helper in `src/Infernix/CLI.hs` to seed the field with the
   supported default for each execution context.
3. Use `runHostTool hostConfig <toolName> args` (helper in `src/Infernix/HostTools.hs`) at the
   call site. Never write `proc "<bare-name>"` directly.
4. Document the field + supported defaults in this manifest doc (the per-tool table above).
5. The Haskell-style lint gate (`disallowedProcCommands`) recognizes the new name automatically
   because it reads the schema field list.

## Validation

- `cabal build all` — every decoder field must exist in the schema.
- `infernix test lint` — the Haskell-style lint gate rejects any `proc "<bare-name>"` whose name
  matches a `ToolPaths` field. Adding a new command without adding the schema field first fails
  this check.
- `grep -rEn '\bproc "(docker|kubectl|helm|kind|cabal|ghc|ghcup|npm|node|python3|poetry|protoc|git|tar|curl|apt-get|brew|skopeo|sudo|systemctl)"' src/ test/` returns zero matches.

## Cross-References

- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md) — overall
  configuration substrate.
- [../development/no_env_vars.md](../development/no_env_vars.md) — developer-facing rules.
- [cluster_config_manifest.md](cluster_config_manifest.md) — the matching cluster-wiring manifest.
