# Infernix Improvements From mattandjames

This note records the repo practices from `~/mattandjames` that are worth importing into
`infernix`.

It is intentionally about repository structure, documentation discipline, CLI shape, and workflow
contracts. It is not a proposal to copy product-specific features such as the offline browser model,
Keycloak flow, or the single-runtime `llama-server` stack.

## Strongest Recommendations

- Strengthen root-document governance. `mattandjames` treats `README.md`, `AGENTS.md`, and
  `CLAUDE.md` as governed docs with explicit `Status`, `Supersedes`, and authoritative-reference
  rules. `infernix` should adopt that stricter model so root docs are clearly either canonical or
  reference-only.
- Replace the handwritten CLI surface with a parser-driven one. `mattandjames` keeps command
  parsing and help generation in one definition. `infernix` still has hand-maintained dispatch plus
  separate hard-coded help text, which is a drift surface.
- Move the Linux outer-container story toward an image-as-artifact model. `mattandjames` executes
  against the baked-in repo copy and bind-mounts only `.data/`. `infernix` should move the Linux
  lanes in that direction, while keeping the explicit Apple host-native exception for real Apple GPU
  access.
- Consolidate route templating. `mattandjames` keeps its Gateway routes in one template. `infernix`
  currently spreads them across multiple `chart/templates/httproutes/*.yaml` files and mirrors that
  fragmentation in chart lint.

## Engineering-Doc Practices To Import

- Add an `implementation_boundaries` engineering document. The `mattandjames` version is a strong
  model for ownership matrices, adapter-local versus shared-contract types, instance placement, and
  module-boundary rules. `infernix` currently spreads those rules across Haskell, Python,
  PureScript, and frontend-contract docs without one authoritative ownership document.
- Promote testing doctrine into engineering docs. `mattandjames/documents/engineering/testing.md`
  is stronger than `infernix/documents/development/testing_strategy.md` because it defines core
  principles, authoritative entrypoints, preflight expectations, unsupported paths, and per-layer
  validation obligations. `infernix` should have that same kind of canonical test doctrine.
- Expand `documents/engineering/storage_and_state.md`. The `mattandjames` version starts with an
  owner/durability table and then explains failure-mode rules and cleanup contracts. `infernix`
  currently has the right broad split between durable and derived state, but it should be much more
  explicit about ownership, failure tolerance, and lifecycle rules.
- Add a portability document. `mattandjames/documents/engineering/portability.md` cleanly
  separates portable application invariants from local-harness substrate details. `infernix` needs
  that even more because its Apple host-native lane and Linux container lanes are easy to conflate.
- Add a real monitoring doctrine if monitoring remains first-class. The `mattandjames` monitoring
  doc is useful not because of the exact stack, but because it states required outcomes, low-cardinality
  rules, typed event expectations, and launch-gate consequences in one place.

## Haskell-Guide Practices To Import

- Rewrite `documents/development/haskell_style.md` in the shape of
  `mattandjames/documents/engineering/haskell_code_guide.md`.
- Separate hard gates from review guidance. `infernix` should clearly state which rules are
  mechanically enforced and which remain code-review doctrine.
- Add an enforcement-model section that points to the actual implementation in
  `src/Infernix/Lint/HaskellStyle.hs`, including formatter, linter, `cabal format`, and warning
  gate behavior.
- Distinguish repository hard-gate inputs from editor-only guidance.
- Add review guidance for module shape, function shape, effect-boundary clarity, and typed control
  flow.
- State the fail-fast rule explicitly: builds and validation should fail on hard-gate violations,
  but should not silently rewrite tracked source.
- Keep `ormolu`. The value to import is the document structure and doctrine, not a switch to
  `fourmolu`.

## Documentation-Structure Practices To Import

- Use more `TL;DR` or `Executive Summary` sections in engineering docs where the topic is broad.
- Include explicit “current status” notes when a document mixes implemented behavior and target
  direction.
- Add validation sections when a document defines a contract that should be proven by tests or
  lint.
- Prefer docs that answer four questions directly:
  what is the rule, what is current versus target, how is it validated, and what is local substrate
  detail versus true platform contract.

## Practices Not To Copy Directly

- Do not copy the “everything runs in the container or cluster” rule. `infernix` must keep the
  Apple host-native inference exception.
- Do not copy the checked-in generated PureScript policy. `infernix` has already chosen the
  untracked generated-contract path.
- Do not copy app-specific docs such as offline-browser architecture or IndexedDB specifications.
- Do not copy `fourmolu` just because `mattandjames` uses it. `infernix` can keep `ormolu` and
  still adopt the better Haskell-guide structure.

## Bottom Line

The main lesson from `mattandjames` is not a different product architecture. It is tighter
repository governance:

- stricter source-of-truth discipline
- cleaner CLI ownership
- cleaner outer-container boundaries
- more explicit engineering doctrine
- better separation between enforced rules and review guidance

Those changes would make `infernix` easier to keep DRY, easier to validate, and harder to let
drift semantically.
