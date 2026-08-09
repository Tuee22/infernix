# Haskell Style

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the authoritative Haskell formatting, linting, and compiler-warning policy.

## Executive Summary

- `ormolu`, `hlint`, `cabal format`, and the Haskell build warning policy are the supported
  mechanical gates for repo-owned Haskell code.
- Repository hard gates are enforced by commands; editor tooling is optional local convenience.
- Review doctrine focuses on module boundaries, small typed helpers, clear effect boundaries, and
  typed control flow instead of shell-heavy orchestration.
- Supported validation is fail-fast: it reports drift and stops; it does not silently rewrite
  tracked source.

## Hard Gates

- `ormolu` is the formatter for repo-owned Haskell source
- `cabal format` is the formatter for `infernix.cabal`
- `hlint` provides lint checks
- strict compiler warnings are enabled and treated as errors on the supported validation path
- formatting drift in repo-owned Haskell sources fails the style gate
- Cabal formatting drift fails the style gate
- `hlint` findings fail the style gate unless the repo deliberately carries a suppression

## Editor-Only Guidance

- use format-on-save, Haskell Language Server, or editor `hlint` integration if they help local
  iteration, but those editor integrations are not part of the repo contract
- local editor plugins may surface warnings earlier, yet the authoritative pass or fail result
  still comes from the repo validation commands
- do not rely on editor-specific rewrites, template expansion, or hidden generated files to satisfy
  repository policy

## Review Doctrine

- `Module shape:` keep ownership boundaries obvious; Haskell modules own the control plane, route
  registry, validation entrypoints, and service orchestration rather than delegating those concerns
  to shell wrappers or sidecar scripts. The only supported shell exception is the thin
  `bootstrap/*.sh` stage-0 host bootstrap surface.
- `Function shape:` prefer small typed helpers and explicit data flow over long imperative
  functions that interleave parsing, shell invocation, mutation, and rendering.
- `Effect boundaries:` keep `IO`, process execution, filesystem mutation, and environment probing
  near the edge so the inner domain logic stays testable and easy to reason about.
- `Native boundary:` keep repo-owned implementation in Haskell. Version-controlled native sources
  are forbidden, including `.c`, `.h`, `.cc`, `.cpp`, `.m`, `.mm`, `.hsc`, C/C++ header variants,
  CUDA, assembly, Metal, Swift, C2HS, and C-- sources. Cabal `c-sources:`, `cxx-sources:`,
  `asm-sources:`, and `cmm-sources:` declarations and CPP definitions that synthesize a native
  boundary are likewise forbidden. Embedding native source, a native-source writer, or its
  compiler invocation in Haskell/Python/shell/JavaScript/configuration text is an equivalent
  violation; native
  implementation inside upstream dependencies is allowed. Do not replace native shims with direct
  FFI declarations, inline C, `System.Process.Internals`, or equivalent relocation. Internal
  Haskell modules may instead encapsulate public APIs from packages such as `filelock`, `process`,
  and `unix`. Direct `foreign import` is forbidden throughout repository-owned Haskell, including
  read-only observers. Darwin process-birth observation uses the registry-backed Haskell
  implementation, and Apple engine-footprint observation uses the fixed bounded
  `/usr/bin/top` plus `/usr/bin/footprint` kernel.
- `Typed control flow:` prefer ADTs, records, and pattern matching over stringly mode switches,
  sentinel values, or silently ignored cases. The type-driven enforcement mechanisms of the managed
  state transitions doctrine — hidden-constructor newtypes via GHC export lists, one honest mint,
  rank-2 region leases (`withLease`), and surgical `LinearTypes` — are the complement to these
  ADT-over-sentinel and `-Werror` rules; see [Managed State Transitions](../architecture/managed_state_transitions.md)
  for the canonical home.
- `Bounded provisioning:` Apple engine materialization may select only closed adapter/operation
  identities through the package-internal `Infernix.Engines.Provisioning` facade. Its opaque
  nominal `ProvisioningGrant s` and indexed `ProvisioningSession s result` remain inside
  `withProvisioningGrant`'s rank-2 region; do not add a raw executable/argv constructor, expose the
  session interpreter, call `System.Process` from an artifact module, or delegate back to the
  unbounded Poetry helpers.
- `Case shape:` avoid hanging `case` expressions such as `foo <- case ...`, `bar -> case ...`, or
  `pure (case ...)`; make the `case` the outer expression or move the branch logic into a named
  helper.
- `Type aliases:` when a function signature uses a `type` synonym, put a comment immediately above
  it showing the full expanded type.
- `Repository discipline:` treat unsupported convenience fallbacks as design debt rather than
  widening the supported contract silently, and preserve the generated-artifact hygiene rules.
- `CLI parsing:` CLI entry points flow through the command-registry layer in
  `src/Infernix/CommandRegistry.hs`; the registry's metadata layer owns parsing, help text, and the
  generated CLI-reference output from the same command inventory.

## Enforcement Model

- `src/Infernix/Lint/HaskellStyle.hs` owns the exact source inventory and repo-specific readability
  rules. Its `runHaskellStyleLintWith` seam accepts formatter and linter callbacks;
  `test/haskell-style/Spec.hs` supplies the heavyweight in-process implementations so production
  executables do not link those libraries.
- the root package's `infernix-haskell-style` component pins and links `ormolu ==0.8.0.2` and
  `hlint ==3.10`. The solver-isolated `test/cabal-format/infernix-cabal-format.cabal` package pins
  and links `Cabal ==3.16.1.0`. The package boundary is load-bearing: enabling two test suites in
  one package still gives Cabal one solver universe, while Ormolu and Cabal 3.16 require
  incompatible `Cabal-syntax` versions. Neither check installs tools at runtime, discovers a
  formatter through `PATH`, or starts nested `ormolu`, `hlint`, or caller-shaped `cabal` processes.
- both lint processes have baked 1024 MiB RTS heap caps and reject caller-supplied RTS overrides.
  Live `GHC.RTS.Flags` assertions prove that each process entered with that exact cap, while the
  Haskell-style manifest fixture requires exact equality between the top-level Cabal test-suite
  stanzas and the constructor-derived closed toolchain vocabulary, pins every corresponding
  per-component RTS row, and rejects a global `cabal.project` override.
- formatter-gate repository discovery explicitly ignores the operator host manifest. Missing or
  stale host-schema state therefore cannot prevent either focused component from locating and
  checking the worktree.
- source discovery recursively checks `app/`, `src/`, and `test/`. The only exclusions are the four
  exact paths in `Infernix.Lint.Proto.generatedHaskellProtoFiles`; their generator-exact bytes and
  tree shape are governed by `infernix lint proto` plus `proto/haskell-bindings.sha256`. A similarly
  named handwritten file remains in the Ormolu, HLint, and readability inventory.
- the Ormolu callback recreates `ormolu --mode check` semantics for every inventory path, including
  Cabal component discovery, source-type detection, and `.ormolu` fixity/module-re-export
  refinement, then compares the rendered text without rewriting the source.
- the HLint callback passes that same exact inventory to `Language.Haskell.HLint.hlint`; any finding
  fails the gate.
- the Cabal-format package reads both `infernix.cabal` and its own package manifest with the pinned
  Cabal API and compares `showGenericPackageDescription` with the tracked bytes. The closed
  `ToolchainCabalFormat` invocation runs that package as a sequential top-level child of the same
  build-memory authority and keeps its build directory below the repo-root `.build/`, outside the
  recursively styled `test/` tree. Its project fixes GHC 9.12.4, disables environment-file writes,
  carries a bounded standalone fallback, and the spawn boundary refuses sibling
  `cabal.project.local` or `cabal.project.freeze` overlays. This is the pinned `cabal format`
  payload without a temporary file, nested Cabal process, or in-place rewrite.
- focused negative fixtures require a deliberately unformatted Haskell module and a module
  producing exactly one HLint idea to fail in `infernix-haskell-style`; a deliberately de-formatted
  but valid Cabal manifest must fail in `infernix-cabal-format`.
- `ormolu` and `hlint` remain explicit forbidden bare-`proc` command names even though their
  `HostTool` constructors are retired, so reintroducing an ambient executable path fails the same
  no-PATH lint as other host tools.
- the style gate rejects every direct `foreign import` in repository-owned Haskell; there is no
  observer allowlist
- the repo-owned files gate (`infernix lint files`) rejects the governed native-source extension
  set, Cabal native-source fields and native-token CPP definitions, and embedded native
  implementation/compiler markers in repository implementation languages. Lifecycle locking uses
  the public nonblocking exclusive `filelock` API
  while keeping the raw token inside a hidden-constructor, rank-2
  `Lease s ClusterMutationLocked` region. Bounded subprocess supervision uses public
  `System.Process` and `System.Posix` APIs behind its internal module: the parent starts one
  self-exec anchor with closed inherited descriptors, an independent process group, an explicit
  environment, and standard-stream pipes; that anchor starts and reaps the supervisor. A total
  length-bounded typed framed protocol and hidden linear phase transitions inside a rank-2 session
  region make durable activity publication a type-level prerequisite for target start
- the style gate enforces the engine-runtime import boundary and the shared-library
  import boundary described in
  [implementation_boundaries.md](../engineering/implementation_boundaries.md)
- the style gate carries the managed-state capability-gating rules that back the raw primitives the
  type system cannot chokepoint: `escapeTokenViolations` (`unsafeCoerce` / `unsafePerformIO` in the
  evidence modules), `rawDestructiveViolations` (raw `rm -rf` / `docker exec … rm`),
  `emptySubprocessEnvViolations` (`env = Just []`), `unboundedExecViolations` (raw unbounded process
  spawn — `readCreateProcessWithExitCode` / `createProcess` / `waitForProcess` and peers — in
  production `src/Infernix/` outside `Infernix.Cluster.Subprocess.runBoundedCommand`),
  `unboundedHttpViolations` (raw `withResponse` for the upstream model download outside the
  bounded-HTTP wrapper), `threadDelayViolations` (raw `threadDelay` readiness/poll loops in
  production `src/Infernix/` outside the `Infernix.Evidence.Readiness.awaitReadiness` kernel and a
  deliberately shrinking backoff/heartbeat exemption list), and `unboundedEngineSpawnViolations` (raw
  engine subprocess spawn — `readCreateProcessWithExitCode` / `createProcess` / `waitForProcess` —
  outside the capped-engine kernel `Infernix.Runtime.CappedEngine` and a shrinking exemption list,
  routing public engine launch through an opaque `ExecutableModel` whose compiled, resource-indexed
  grant has been paired with its matching live enforcer; the package-internal capped-engine region
  applies the resulting resident-memory ceiling). Their canonical doctrine is
  [Managed State Transitions](../architecture/managed_state_transitions.md); the engine-spawn rule's
  canonical home is [Bounded Inference Memory](../architecture/bounded_inference_memory.md)
- `appleArtifactProvisioningViolations` rejects `System.Process`, raw spawn/wait functions,
  legacy `ensurePoetryExecutable` / `ensurePoetryProjectReady` delegation, and direct
  `runBoundedCommand` use across the Apple facade, its hidden implementation, the artifact
  transaction, and provisioning modules. Only the hidden provisioning facade may interpret its
  closed commands through the bounded subprocess kernel
- `infernix test lint` runs both in-process formatter checks together with the repo-owned files,
  chart, proto, docs, Python, and build-warning checks

## Validation

- `infernix test lint` is the canonical static-quality entrypoint and owns both solver-isolated
  formatter invocations; no bare Cabal command is a supported validation instruction
- supported validation is fail-fast and stops on drift instead of rewriting tracked files

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/build_artifacts.md](../engineering/build_artifacts.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
- [Bounded Inference Memory](../architecture/bounded_inference_memory.md)
