# Dependency Management

**Status**: Authoritative source
**Referenced by**: [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Document the supported Haskell dependency posture, including the project-wide
> `cabal.project` flags that unlock current upstream packages against the project's GHC, plus the
> narrow Python-side pin that keeps the generated protobuf stubs runnable.

## Python `protobuf` / `grpcio-tools` compatibility pin

`python/pyproject.toml` pins `grpcio-tools = ">=1.73.0,<1.74"`. The pin exists because
`grpcio-tools 1.74`+ (through at least `1.82.0`) ship a `protoc` that stamps generated `*_pb2.py`
stubs with protobuf **gencode 7.35**, while the project's runtime `protobuf` resolves to the
`^6.31.1` line (`6.33.6`). At import time `protobuf`'s `runtime_version` guard rejects a stub whose
gencode is newer than the runtime (`gencode 7.35.0 > runtime 6.33.6`), which breaks
`poetry run check-code`, `infernix test unit`'s Apple-engine adapter import, and the cluster runtime
**image build** (`docker build ... && poetry run check-code`). `grpcio-tools 1.73.x` stamps
gencode 6.31, which the 6.x runtime accepts. The lockfile (`python/poetry.lock`) is `.gitignore`d /
`.dockerignore`d, so the tracked `pyproject.toml` constraint is the single durable source of the
resolution for both host venvs and the fresh in-image `poetry install`. Revisit the pin only
together with a coordinated bump of the runtime `protobuf` major and the generated-stub regeneration.

## Toolchain Pin

The supported Haskell toolchain is `ghc-9.12.4`. The cabal manifest declares it via
`tested-with: ghc ==9.12.4`, and `cabal.project` pins it via `with-compiler: ghc-9.12.4`. The
formatter tools `ormolu` and `hlint` install into `./.build/haskell-style-tools/bin/` through
`cabal install` against the same project compiler; `src/Infernix/Lint/HaskellStyle.hs` manages
that install.

## Project-wide `cabal.project`

The repo carries `cabal.project` at the worktree root. It performs three roles:

- pins the supported compiler with `with-compiler: ghc-9.12.4`;
- enables `allow-newer: *:base, *:template-haskell` so transitive Hackage packages whose declared
  upper bounds lag behind the project's GHC resolve cleanly;
- retains targeted package-specific `allow-newer` entries for the existing `lens-family`,
  `proto-lens`, `binary`, and setup-tool closure;
- carries any `source-repository-package` overrides needed when an upstream package has a real API
  break against `base 4.22` rather than a conservative declared bound. None are required today.

## Why wildcard `allow-newer`

The `dhall` Haskell library (used to decode `infernix.dhall` in-process) and its
transitive dependency closure (`serialise`, `cborg`, `cborg-json`, `half`) declare conservative
upper bounds against `base` and `template-haskell` that lag a release or two behind the project
toolchain. The wildcard `allow-newer: *:base, *:template-haskell` relaxes those declarations
without broadening the wildcard further; the targeted package-specific rows cover the remaining
`lens-family`, `proto-lens`, `binary`, and setup-tool closure.

If a future GHC bump uncovers genuine breakage in one of those packages, the supported response is
to add a targeted `source-repository-package` stanza pointing at a patched fork in `cabal.project`,
not to broaden the wildcard further.

## Hackage Index Pin

`cabal.project` does not pin an `index-state`. Reproducibility comes from the explicit version
bounds in `infernix.cabal`, the wildcard `allow-newer` entries for the GHC-bound axes above, and
the targeted package-specific relaxations already recorded in `cabal.project`. Operators who need
byte-identical dependency closure across hosts can add an `index-state:` line locally; it is not
part of the supported contract.

## Cross-References

- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)
- [../development/haskell_style.md](../development/haskell_style.md)
- [build_artifacts.md](build_artifacts.md)
