# Repo DRY Cleanup

This document collects the repository-improvement changes discussed in the current conversation.
It defines one recommended cleanup path that leads to a DRY repository layout. It is a proposal,
not a statement that the work is already implemented.

## Goals

- reduce duplicated Dockerfile logic
- make the runtime model honest, especially on Apple Silicon
- remove misleading layout and naming choices
- reduce duplicated Python substrate code
- reduce duplicated route, publication, and chart contract definitions
- reduce duplicated CLI and helper logic
- reduce documentation drift by keeping one canonical home per topic
- simplify the outer-container launcher model
- keep generated artifacts and caches out of tracked source paths

## 1. Collapse the Linux Dockerfile Story

Current reality:

- `docker/linux-base.Dockerfile` is not a meaningful standalone runtime image
- the effective runtime image set is `infernix-linux-cpu` and `infernix-linux-cuda`
- most of the `linux-cpu` and `linux-cuda` build logic is shared

Recommended cleanup:

- remove `docker/linux-base.Dockerfile`
- replace `docker/linux-cpu.Dockerfile` and `docker/linux-cuda.Dockerfile` with one shared file named `docker/linux-substrate.Dockerfile`
- build the CPU and CUDA images from that one file with build arguments such as:
  - `BASE_IMAGE`
  - `PYTHON_PROJECT`
  - `RUNTIME_MODE`
- keep only the substrate-specific delta where it is genuinely required

Expected result:

- one source of truth for the shared Linux substrate toolchain and build flow
- no fake intermediate base image to explain or maintain
- clearer mapping between the repo model and the actual runtime image set

## 2. Remove the `nvkind` Host-Path Workaround

Current reality:

- the `linux-cuda` lane uses `nvkind`
- the launcher image does not include Go
- when `nvkind` is missing, the code falls back to spawning a separate `golang` container through the host Docker socket
- that fallback forces a host-visible handoff path for the built `nvkind` binary

Why this is a problem:

- it is an unnecessary Docker-socket and path-translation workaround
- it is one of the main reasons the current outer-container design is more convoluted than it should be

Recommended cleanup:

- stop building `nvkind` through a secondary host-Docker-launched builder container
- build `nvkind` in a multi-stage Docker build and copy only the final binary into the CUDA image
- remove the host-visible `nvkind` handoff path from the runtime flow

Expected result:

- no host-visible `.build/tools/nvkind` bridge
- no dependence on the universal repo bind mount for `nvkind`
- cleaner CUDA launcher behavior

## 3. Make the Runtime Model Honest

Current reality:

- Apple Silicon inference must be host-native to use Metal GPU execution and unified memory truthfully
- the Linux CPU and Linux CUDA lanes are containerized inference substrates
- treating all three runtime modes as equivalent container substrates is conceptually false

Recommended cleanup:

- describe the platform as:
  - one host-native Apple Silicon inference lane
  - one containerized Linux CPU lane
  - one containerized Linux CUDA lane
- state explicitly that Apple breaks container parity at the inference boundary by design
- keep the shared abstraction at the control-plane, publication, config, Pulsar, protobuf, and routed API/UI levels

Related cleanup:

- fix docs and codepaths that currently imply Apple has a normal substrate image story when the actual inference requirement is host-native
- keep the repo language aligned with the fact that there are only two functional repo-owned Linux runtime images

## 4. Simplify `compose.yaml` and the Outer-Container Model

Current reality:

- the supported launcher container bind mounts the whole repo into `/workspace`
- it also keeps separate volumes for `/opt/build`, `/root/.cabal`, and `web/node_modules`
- the broad repo mount is doing more than is likely necessary

Recommended cleanup:

- adopt an image-snapshot model for the outer-container launcher:
  - make changes locally
  - rebuild the image when needed
  - run the launcher against that image snapshot
- keep a host bind mount only for `./.data`, because that is the persistent state layer used across ephemeral cluster teardown
- keep named volumes for `/opt/build` and `/root/.cabal`
- remove the universal `.:/workspace` bind
- remove the `web/node_modules` runtime volume and rely on the image-baked toolchain

Expected result:

- a cleaner and more predictable launcher model
- less accidental coupling between runtime behavior and the live checkout
- simpler reasoning about what truly needs to persist on the host

## 5. Remove `npx` From Supported Workflows

Current reality:

- the repo uses `npx` as a convenience wrapper for Playwright
- this is not functionally required

Recommended cleanup:

- replace all `npx` Playwright calls with `npm --prefix web exec -- playwright ...`

Expected result:

- one less tool wrapper to reason about
- better consistency with the rest of the npm-managed toolchain usage

## 6. Dedupe the Python Substrate Layout

Current reality:

- `python/apple-silicon`, `python/linux-cpu`, and `python/linux-cuda` are nearly identical today
- most adapter modules are duplicated byte-for-byte
- the Haskell runtime is currently wired to per-substrate Python project directories

Recommended cleanup:

- collapse the Python layout to a single root `python/pyproject.toml`
- use one shared `python/adapters/` tree
- update the Haskell runtime contract to stop assuming `python/<runtime-mode>`
- keep runtime-specific behavior inside the shared tree only where the adapter logic truly diverges

Expected result:

- one Python dependency boundary
- one adapter tree
- much less duplicated Python code

## 7. Fix the Misleading `Generated` Naming

Current reality:

- `src/Generated/Contracts.hs` is hand-written source code
- `web/src/Generated/Contracts.purs` is the actual generated artifact

Recommended cleanup:

- move the hand-written Haskell module out of `src/Generated/`
- place it at `src/Infernix/Web/Contracts.hs`
- reserve `Generated` directories for real generated outputs only

Expected result:

- clearer ownership and semantics
- less confusion for contributors reading the tree

## 8. Keep Generated Artifacts Out of Git

Current reality:

- ignore rules already cover generated Python caches and related artifacts
- the larger issue was tracked-index drift, not missing ignore rules

Recommended cleanup:

- keep generated outputs, caches, and lock artifacts that are meant to be disposable out of the tracked index
- examples discussed in this conversation:
  - `tools/generated_proto/`
  - tracked `__pycache__` content
  - tracked `*.pyc`
  - `web/spago.lock`
- treat this as repo hygiene, not as an excuse to add more supported wrapper scripts

Expected result:

- less noise in `git ls-files`
- less confusion about what is source of truth versus generated output

## 9. Collapse the Route and Publication Contract to One Source

Current reality:

- the route inventory is defined in multiple places
- Haskell simulation state hard-codes the route list
- the chart renders one file per `HTTPRoute`
- chart lint repeats the route expectations
- `chart/values.yaml` embeds publication JSON that repeats the same route inventory
- the docs repeat the route set in several places

Recommended cleanup:

- define one Haskell-owned route registry that records:
  - path prefix
  - purpose label
  - backend service identity
  - rewrite behavior
  - demo-only versus always-on visibility
  - publication-upstream metadata
- drive all route-aware outputs from that registry:
  - simulated route inventory
  - publication-state rendering
  - Helm `HTTPRoute` rendering inputs
  - chart lint expectations
  - route-oriented documentation summaries
- replace the per-route hand-maintained Helm files with one data-driven route template plus helpers

Expected result:

- one route contract
- one publication contract
- much lower risk of route drift across code, chart, lint, and docs

## 10. Stop Committing Generated Demo and Publication Payload Copies

Current reality:

- `chart/values.yaml` contains serialized demo-config and publication payload blobs
- those blobs duplicate data already rendered by Haskell during `cluster up`

Recommended cleanup:

- remove the committed generated payload copies from `chart/values.yaml`
- keep `chart/values.yaml` focused on stable structural defaults
- treat demo-config payloads and publication payloads as generated deployment inputs only
- have `cluster up`, chart rendering, and chart lint all consume the same generated values material

Expected result:

- no stale committed copy of generated runtime state
- cleaner chart defaults
- one rendering path for generated deployment payloads

## 11. Consolidate Shared Haskell Workflow Helpers

Current reality:

- web dependency checks are duplicated across the CLI path and cluster path
- platform command availability checks are duplicated
- small shared literals such as the demo-config banner are duplicated

Recommended cleanup:

- move shared workflow checks into one Haskell support module
- expose one helper for:
  - web toolchain presence
  - `npm --prefix web ci` readiness
  - platform command availability
  - shared generated-file banner constants
- reuse those helpers from the CLI, cluster, and lint paths instead of re-declaring them locally

Expected result:

- less repeated Haskell code
- less drift between runtime paths
- simpler future maintenance

## 12. Make the CLI Surface Derive from One Command Registry

Current reality:

- command dispatch is handwritten
- CLI help text is a separate handwritten copy
- CLI reference docs repeat the same command list again

Recommended cleanup:

- define one Haskell-owned command registry for the supported `infernix` surface
- use that registry to drive:
  - argument dispatch
  - help text
  - the canonical CLI reference document content
- keep `documents/reference/cli_surface.md` as a short summary that points at the canonical CLI reference

Expected result:

- one command inventory
- less risk that help text, implementation, and docs diverge
- clearer CLI maintenance rules

## 13. Make the Governed Docs More Canonical and Less Repetitive

Current reality:

- the same workflow and topology details are repeated across `README.md`, governed docs, runbooks,
  and plan material
- some of those repeated copies already differ
- `AGENTS.md` and `CLAUDE.md` are near-duplicate workflow documents

Recommended cleanup:

- follow `documents/documentation_standards.md` strictly:
  - `README.md` stays an orientation layer
  - `documents/` keeps one canonical home per topic
  - supporting docs summarize and link back instead of restating full contracts
- make these canonical homes explicit:
  - runtime-mode table and semantics: `documents/architecture/runtime_modes.md`
  - local operator commands: `documents/development/local_dev.md`
  - route contract: `documents/engineering/edge_routing.md`
  - CLI command inventory: `documents/reference/cli_reference.md`
  - Python adapter doctrine: `documents/development/python_policy.md`
- reduce supporting documents to audience-specific deltas:
  - `README.md` links to canonical command docs instead of carrying full parallel quick-start copies
  - runbooks carry only operational nuance beyond the canonical local-dev workflow
  - `documents/reference/cli_surface.md` remains a short command-family overview
- move repository-level assistant workflow doctrine into one canonical source and keep `AGENTS.md`
  and `CLAUDE.md` as thin aligned entry documents

Expected result:

- less documentation drift
- clearer ownership of each topic
- better alignment with the repo’s stated documentation standards

## Recommended Order

1. Collapse the Dockerfiles and remove `linux-base`.
2. Fix the CUDA `nvkind` bootstrap so it no longer depends on a host-visible binary handoff.
3. Simplify `compose.yaml` to keep only the host persistence mounts that are genuinely required.
4. Remove `npx` from the remaining workflows.
5. Collapse the Python tree to one root project and one shared adapter tree.
6. Move `src/Generated/Contracts.hs` to `src/Infernix/Web/Contracts.hs`.
7. Collapse the route and publication contract to one Haskell-owned source and one data-driven chart route template.
8. Remove committed generated demo-config and publication payload copies from `chart/values.yaml`.
9. Consolidate shared Haskell workflow helpers.
10. Make the CLI help and CLI reference derive from one command registry.
11. Finish the tracked generated-artifact cleanup and keep the ignore contract strict.
12. Align the docs and plan language around the honest runtime model, canonical topic ownership, and summary-versus-source discipline.

## Summary

The main cleanup theme is to stop pretending the repo has more symmetry than it really does.
There are two functional Linux substrate images, one host-native Apple inference lane, one
unnecessary Docker base layer, one avoidable `nvkind` bootstrap workaround, one route contract
spread across code, chart, lint, and docs, one duplicated CLI surface, one misleading `Generated`
module location, and a Python plus documentation tree that are more duplicated than the current
behavior justifies.
