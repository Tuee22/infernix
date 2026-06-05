# Dependency Management

**Status**: Authoritative source
**Referenced by**: [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Document the supported Haskell dependency posture, including the project-wide
> `cabal.project` flags that unlock current upstream packages against the project's GHC.

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

The `dhall` Haskell library (used to decode `infernix-substrate.dhall` in-process) and its
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
