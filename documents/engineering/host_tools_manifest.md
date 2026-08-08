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
- The Haskell binary loads this file at startup via the `dhall` library. Closed cluster commands
  declare their exact domain `HostTool` set, and the opaque compiler resolves only those selected
  tools from `HostConfig.toolPaths.*`, rejecting empty, nonabsolute, missing, and nonexecutable
  paths. The two fixed Bash pipelines declare Bash explicitly; it is not a universal watchdog
  dependency.
- The same generated manifest carries exactly 36 production command policies. Retry and failure
  behavior are proper Dhall unions and are refined into an opaque, exhaustive policy plan.
- Bootstrap shell scripts use the same paths — either as hardcoded constants written into the
  script (for the small set of commands that run before the launcher binary exists) or by
  delegating to the binary after it does.
- No project command selects its primary executable through the operator's shell search path. The
  command kernel owns a minimal `PATH` derived only from nonempty absolute manifest tool directories
  plus fixed system fallbacks; callers cannot replace it. The Haskell-style lint gate rejects both
  `proc "<bare-name>"` and direct `findExecutable` / `findExecutables` discovery for manifest-owned
  host tools.

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
      , python311 : HostTool
      , llamaCli : HostTool
      , whisperCli : HostTool
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
      , sysctl : HostTool
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

let RetryPolicy =
      < Never
      | Bounded : { attempts : Natural, backoffMicros : Natural }
      >

let FailureClass =
      < Fatal
      | TransientThenFatal
      | IdempotentAbsence
      >

let CommandPolicy =
      { timeoutMicros : Natural
      , retry : RetryPolicy
      , failureClass : FailureClass
      }

let CommandPolicies =
      { kindRead : CommandPolicy
      , kindCreate : CommandPolicy
      , kindDelete : CommandPolicy
      , nvkindCreate : CommandPolicy
      , kubectlRead : CommandPolicy
      , kubectlApply : CommandPolicy
      , kubectlDelete : CommandPolicy
      , kubectlWait : CommandPolicy
      , kubectlExec : CommandPolicy
      , helmUpgrade : CommandPolicy
      , helmDependency : CommandPolicy
      , helmRepository : CommandPolicy
      , helmRender : CommandPolicy
      , dockerExec : CommandPolicy
      , dockerProbe : CommandPolicy
      , dockerBuild : CommandPolicy
      , dockerInspect : CommandPolicy
      , dockerPull : CommandPolicy
      , dockerTag : CommandPolicy
      , dockerCopy : CommandPolicy
      , dockerStreamImport : CommandPolicy
      , dockerNetwork : CommandPolicy
      , containerRuntimePull : CommandPolicy
      , hostProbe : CommandPolicy
      , hostMutation : CommandPolicy
      , curlProbe : CommandPolicy
      , archiveRead : CommandPolicy
      , gpuUserspaceSync : CommandPolicy
      , imagePublicationLogin : CommandPolicy
      , imagePublicationInspect : CommandPolicy
      , imagePublicationPull : CommandPolicy
      , imagePublicationVerify : CommandPolicy
      , imagePublicationTag : CommandPolicy
      , imagePublicationPush : CommandPolicy
      , imagePublicationRemove : CommandPolicy
      , imagePublicationCopy : CommandPolicy
      }

let HostMemoryFacts =
      { physicalMemoryMib : Natural
      , effectiveMemoryMib : Natural
      }

let HostExecutionContext =
      < AppleHostNative
      | LinuxOuterContainer
      >

in    { hostExecutionContext : HostExecutionContext
      , hostArchitecture : Text
      , toolPaths : ToolPaths
      , filesystem : FilesystemConventions
      , memory : HostMemoryFacts
      , commandPolicies : CommandPolicies
      , playwrightHost : Text
      , controlPlaneContext : Text
      }
```

The schema is reflected from the `HostConfig` decoder type (`infernix internal dhall-schema host`);
the operator's generated manifest is written by `infernix init` to `./infernix-host.dhall`
(gitignored). There is no packaged `.dhall` schema in the repo or launcher image. `hostArchitecture`
stores the normalized native host architecture (`amd64` or `arm64`) used by the `linux-cpu`
publication selector. `commandPolicies` has exactly the 36 fields shown above; test-only subprocess
probes are deliberately not represented in operator configuration. The Linux launcher Dockerfile
embeds that complete default record in its generated host payload. Unit coverage extracts the
literal Dockerfile payload, substitutes only the build-time native architecture value, strictly
decodes it through `HostConfig`, and compares the full result with the typed Linux
outer-container default so a missing field or default-policy drift fails before image build.

`memory` is the only record in this manifest that is **measured rather than declared**. `infernix
init` reads `MemTotal` from `/proc/meminfo` on Linux and intersects it with the cgroup v2 maximum in
force — inside the outer launcher container the first figure is the whole machine's and the second
is what a build actually gets — and reads `sysctl -n hw.memsize` on Darwin, where there are no
cgroups and the two figures are therefore equal. The measurement is fail-closed: `infernix init`
refuses to write a manifest it could not measure, because a build ceiling derived from an unmeasured
host is a declared number wearing a measurement's clothes. Both fields feed
[../architecture/bounded_host_memory.md](../architecture/bounded_host_memory.md): the toolchain
account is a share of `effectiveMemoryMib`, and `infernix init` divides it by a job count into the
untracked repo-root `cabal.project.local`.

A manifest written before a current record exists is refused by name rather than by a raw structural
Dhall type error. Startup fails closed on a manifest it cannot decode — falling through to
convention defaults could misclassify the execution context — so the remedy the diagnostic names is
to delete the file and re-run `infernix init`.

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
| python3.11 | `toolPaths.python311` | `/opt/homebrew/bin/python3.11` | unavailable (empty) |
| llama-cli | `toolPaths.llamaCli` | `/opt/homebrew/bin/llama-cli` | unavailable (empty) |
| whisper-cli | `toolPaths.whisperCli` | `/opt/homebrew/bin/whisper-cli` | unavailable (empty) |
| poetry | `toolPaths.poetry` | `${HOME}/.local/share/pypoetry/venv/bin/poetry` | baked: `/opt/poetry/bin/poetry`; the Apple default is created by the kernel-locked bounded bootstrap, while manifestless fallback checks fixed Homebrew/image/system absolute paths only |
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
| sysctl | `toolPaths.sysctl` | `/usr/sbin/sysctl` | n/a |

`colima` is deliberately not a manifest field. The Apple memory-partition probe may read it through
the fixed bootstrap-adjacent `/opt/homebrew/bin/colima` candidate, but Infernix never manages it and
normal command execution cannot select it from runtime configuration.

The former `tart` field (Haskell record selector `hostTart`) is no longer part of the current
schema. There is no `HostTool.HostTart`, no `AppleTart` prerequisite, and no
Tart-backed command helpers; `infernix internal materialize-metal-engines` now materializes typed
engine-artifact manifests through the headless host lane described in
[apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md). The cleanup
receipt is recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

The Apple defaults assume Homebrew (`/opt/homebrew/bin`) and ghcup. Docker-backed Apple work
requires the current Docker context to already point at a native arm64 Docker daemon; Infernix must
not create or switch Docker contexts, create a Colima VM, or use emulation. The Linux launcher
defaults are baked into the launcher image at build time and updated only by rebuilding the image.
The general Apple Python field remains pinned to Python 3.12. Core ML artifact provisioning selects
only the separately declared Python 3.11 field; `materialize-metal-engines` reconciles both Homebrew
formulae, the `llama.cpp` and `whisper-cpp` formulae that provide the two declared native CLIs, and
Poetry before entering the closed provisioning session. Each native CLI is copied from its declared
path into the candidate payload before hashing and activation; installed runners invoke only that
artifact-local copy. No undeclared interpreter or native CLI candidate is probed.
The exact configured Poetry launcher, not its unwrapped shebang interpreter, is the bounded project
installation executable. Its interpreter, package tree, and runtime libraries are retained as
immutable closure evidence. Protobuf generation uses the exact installed
`python/.venv/bin/python` directly with fixed repository-relative operands, so it does not create a
nested Poetry process.
Apple operators can override individual paths by editing `./infernix-host.dhall`; the
resulting file is consumed on next `infernix <command>` invocation.

## Closed command compilation

Production cluster and image-publication commands are values of the abstract `ClusterCommand`
language in the library-internal `Infernix.Cluster.Command` module. Its renderer emits a primary
`HostTool` and the complete domain-tool set for that command. `compileBoundedCommand` resolves
exactly that set through `HostConfig.hostToolPath`; every selected value must be nonempty, absolute,
present, and executable. Through public `System.Process.createProcess`, the subprocess kernel
self-execs one anchor with `close_fds = True`, `create_group = True`, an explicit environment, and
ordinary `CreatePipe` standard streams. The fresh anchor starts and reaps the separately grouped
supervisor through the same public API, preventing concurrent parent commands from sharing protocol
handles. The required custody protocol starts the supervisor inside the anchor group and a
self-exec pin inside the supervisor group. Each provisional PID/group/birth identity is forwarded
to and reobserved by the parent before an opaque acknowledgement permits that helper to detach. All
helper links carry maximum-bounded JSON messages in eight-hex-digit length-prefixed standard-stream
frames, with input and output bytes base64-encoded inside the frame.

The parent live-verifies the final owner, anchor, supervisor, and self-exec pin PID, group, and
birth identities. An opaque rank-2 session with linear phase transitions permits target creation
only after durable version-3 activity publication and a retained-pin acknowledgement. That record
keeps `command*` for the anchor and `watchdog*` for the supervisor as persisted-format compatibility
keys and stores the exact pin under compatibility `targetGroupLeader*` keys. A bounded, fsynced
incoming-intent filename carries the same identities before the payload write; common-boot names
use the version-3 encoding and fixed-width distinct-boot names use version 4. The supervisor then
owns the sole public `System.Posix` fork/exec boundary: the arbitrary target begins in the
supervisor group behind an inner gate, moves into the recorded pin group, and cannot execute until
its supervisor-owned PID is observed in that group. The target is an unreaped child, not a
persisted exact birth identity.
`executeFile` uses a close-on-exec report pipe for setup/exec failure provenance. Parent death
before publication leaves no target; later recovery decodes version 1/2 records and removes any
lease only after proving the recorded anchor, supervisor, and pin-led target groups absent.
Fixed Bash pipelines declare Bash and carry Docker's resolved absolute path as a nested argument. A
kubectl-only command does not fail merely because Bash, Docker, or another unrelated domain tool is
unsupported on the active host.

The lock and process packages remain behind library-internal Haskell modules. The lock wrapper uses
`filelock`'s nonblocking exclusive operation and hides its token inside the rank-2
`Lease s ClusterMutationLocked` lifecycle region. Repository-owned native implementation files
(including C/C++/Objective-C/CUDA/assembly/Metal/Swift/C2HS/HSC/C-- sources and headers), Cabal native-source
fields or native-token CPP definitions, embedded native source/compiler paths, direct FFI, inline
C, and `System.Process.Internals` are not supported implementation or host-tool surfaces;
`infernix lint files` enforces the owned-source boundary. Native implementation owned by upstream
`filelock`, `process`, and `unix` packages is allowed.

The operator's raw kubectl compatibility surface is deliberately a separate
`OperatorKubectlCommand`, built by a validator that fixes the recorded kubeconfig target, rejects
target-changing flags, and admits only an explicit observational vocabulary (`get`, `describe`,
`logs`, `top`, `wait`, discovery commands, and read-only grouped subcommands). Mutating verbs,
mutating grouped subcommands, arbitrary plugins, `exec`, and kubectl global profile/cache flags
capable of caller-selected local writes are rejected. It is compiled through a separate bounded
read-policy entry point; raw tokens are never a `ClusterCommand`.

Executable paths are only one part of process context. Hidden-constructor `SubprocessEnv` owns:

- `PATH`, derived from the parent directories of nonempty absolute manifest tool paths plus fixed
  system directories, with no caller-supplied search-path API;
- absolute `HOME` from `filesystem.homeDirectory`;
- absolute `TMPDIR` under `dataRoot`;
- absolute `HELM_CONFIG_HOME`, `HELM_CACHE_HOME`, and `HELM_DATA_HOME` under `dataRoot`.

The closed renderer, not a caller, selects repository cwd for commands whose relative chart,
Dockerfile, or archive paths require it. Kind create/delete and nvkind create take a semantic
`KindScratchKubeconfig` and render command-specific `KUBECONFIG`; nvkind also renders fixed
`KUBERC=off` so its nested kubectl calls cannot consume ambient kuberc state. Neither the
production, operator-kubectl, nor test compiler accepts arbitrary cwd or environment overrides.

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
3. Add the `HostTool` constructor and a semantic `Infernix.Cluster.Command` builder/rendering case.
   The rendered spec declares the tool only where the selected command actually requires it; callers
   do not pass an executable or argv to a generic runner. Never write `proc "<bare-name>"` directly
   or call `findExecutable` / `findExecutables` to discover a manifest-owned tool.
4. Add a generated command-policy field only when the new operation has policy semantics not covered
   by an existing category. Keep the Dhall decoder type, defaults, renderer, opaque
   `CommandPolicyPlan`, and the exact field list in this document synchronized.
5. Document the field and supported defaults in the per-tool table above.
6. The Haskell-style lint gate (`forbiddenBareProcCommands`, derived from the `HostTools.HostTool`
   enum via `hostToolCommandNames`) picks up the new command automatically — adding the `HostTool`
   constructor extends the gate, so it cannot drift from the registered tool set.

## Validation

- `cabal build all` — every decoder field must exist in the schema.
- Host-manifest schema tests must round-trip both proper policy unions and all 36 fields.
  `compileCommandPolicyPlan` tests must reject zero or overflowing timeouts, attempts, and backoffs
  and must select every production `ClusterOperation` exhaustively.
- Command compiler tests must reject empty, relative, missing, and nonexecutable paths for each exact
  domain tool; prove nested Bash/Docker dependencies are checked without checking unrelated domain
  tools; prove non-Bash commands compile without a configured Bash executable; and prove cwd and
  environment values cannot be supplied by callers.
- `infernix test lint` — the Haskell-style lint gate rejects any `proc "<bare-name>"` whose name
  matches a `ToolPaths` field, and rejects `findExecutable` / `findExecutables` outside the lint
  module's own token list. Adding a new command without adding the schema field first fails this
  check.
- `grep -rEn '\bproc "(docker|kubectl|helm|kind|cabal|ghc|ghcup|npm|node|python3|python3\.11|llama-cli|whisper-cli|poetry|protoc|git|tar|curl|apt-get|brew|skopeo|sudo|systemctl)"' src/ test/` returns zero matches, and
  `rg -n 'findExecutable|findExecutables' Setup.hs src test` returns only the lint module's forbidden-token
  list.

## Cross-References

- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md) — overall
  configuration substrate.
- [apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md) — Tart-free
  Apple Metal/Core ML materialization target.
- [../development/no_env_vars.md](../development/no_env_vars.md) — developer-facing rules.
- [cluster_config_manifest.md](cluster_config_manifest.md) — the matching cluster-wiring manifest.
