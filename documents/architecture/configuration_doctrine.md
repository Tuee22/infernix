# Configuration Doctrine

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md), [../development/no_env_vars.md](../development/no_env_vars.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define the supported configuration substrate — typed `.dhall` that is **generated
> by the `infernix` binary, never version-controlled** — the `init` / `test init` create contract,
> the fail-fast-if-missing rule, and the no-env-var, absolute-path discipline that surrounds it.

## TL;DR

- **Zero version-controlled `.dhall`.** No `.dhall` file is checked into the repository. Every
  `.dhall` in the tree is a generated artifact under `.build/` / `.data/` (gitignored) or the
  operator-created `./infernix.dhall` / `./infernix.test.dhall` (also gitignored).
- **The `infernix` binary is the sole generator of every `.dhall`** — including the bodies injected
  into pods via ConfigMap/Secret. Helm never renders or parses Dhall; it only embeds a
  binary-produced string (`nindent`). Schemas are **reflected from the Haskell decoder types**
  (`renderDecoderExpected (Dhall.auto @T)`), so the emitted schema cannot drift from what the
  decoder accepts.
- **Config is created by `init`.** `infernix init` writes the **system contract**
  `./infernix.dhall` (the substrate mode and the pool record that carries the model set) and the
  **machine contract** `./infernix-host.dhall` (this box's tool paths, filesystem, and `node`
  block). `infernix test init` writes the thin `./infernix.test.dhall`. There is
  **no hidden auto-generate-if-absent backstop** inside ordinary `infernix` commands. The Apple
  stage-0 bootstrap wrappers are the explicit convenience exceptions: `up` invokes
  `./.build/infernix init --if-missing` before `cluster up`, while `test` invokes the
  runtime-mode-specific `init --if-missing` before test initialization and `test all`.
- **Everything fails fast when its config is missing**, naming the init to run
  (e.g. `runtime config missing at ./infernix.dhall; run \`infernix init\``), unless the operator
  entered through one of those explicit Apple bootstrap wrappers.
- **The test harness reserves the cluster slot before touching runtime config.** Under the lifecycle
  lock it publishes a process-group reservation with a verified owner birth identity, refuses an
  operator-owned cluster or second live harness, then backs up any existing `./infernix.dhall`.
  The library-internal lock wrapper uses `filelock`'s nonblocking exclusive API and hides the package
  token inside the existing rank-2 `Lease s ClusterMutationLocked` region, so thread/process
  contention and kernel release survive without a residue protocol. The harness then
  installs the generated test config, runs, and restores the backup. A later harness may reclaim a
  definitely dead reservation and reconcile a leftover `.harness-backup` on entry, but only after
  every birth-verified bounded-command activity lease for that reservation owner proves all recorded
  process groups absent. Through public `System.Process`, the kernel self-execs one separately
  grouped anchor with an explicit environment, closed unrelated descriptors, and ordinary
  standard-stream pipes. The supervisor begins inside the anchor group and the self-exec pin begins
  inside the supervisor group; each provisional PID/group/birth identity reaches parent custody
  before that helper may detach. This isolation prevents concurrent parent commands from sharing
  protocol handles. All helper links use a total, maximum-bounded JSON protocol with
  eight-hex-digit length-prefixed frames over standard streams and base64 input/output. A hidden
  rank-2, linear session requires durable version-5 activity publication before the retained pin can
  acknowledge the one-shot start authority and the supervisor may fork the target. The target
  begins behind an inner gate and cannot execute until its supervisor-owned PID is observed in the
  exact pin group. It is owned as an unreaped child, not persisted as an exact birth identity. The
  record retains `command*` (anchor) and `watchdog*` (supervisor) compatibility keys and stores the
  exact self-exec pin under compatibility `targetGroupLeader*` keys. Recovery decodes versions 1
  and 2 but retires any record only after every recorded anchor, supervisor, and pin-led target
  group is proven absent. Before the version-3 payload write, a bounded, fsynced incoming-intent
  basename carries the same exact owner/anchor/supervisor/pin identities. Legacy encodings remain
  decodable, while protected current common-boot and fixed-width distinct-boot names use version 6,
  so recovery of an empty or truncated prewrite does not rely on PID-only inference.
- The `dhall` Haskell library is the only Dhall reader. There is no `dhall-to-json` bridge.
- Every external command the project ever invokes is named in the host manifest by absolute path;
  no `proc "<bare-name>"` / `findExecutable` discovery in Haskell, no bare-name invocations in shell.
- The generated host manifest also contains exactly 36 production command-policy fields. Retry and
  failure modes are proper Dhall unions, not text tags, and Haskell refines every timeout, bounded
  attempt count, and backoff to a positive machine-sized value before a command can compile.
- No Haskell module calls `lookupEnv` / `getEnv` / `getEnvironment` / `setEnv` / `unsetEnv`; no
  infernix-owned `chart/templates/deployment-*.yaml` carries an `env:` block.

## Why

Environment variables split one configuration fact across Haskell reads, chart-template `env:`
injections, bootstrap-shell references, and implicit `PATH` / `HOME` / `KUBECONFIG` /
`DOCKER_HOST` state. The configuration doctrine uses one substrate (typed Dhall) and one
tool-discovery surface (absolute paths in the
host manifest). The hidden-constructor `SubprocessEnv` owns its manifest-derived `PATH`, absolute
`HOME` and `TMPDIR`, and repo-local Helm config/cache/data homes. A closed renderer, rather than a
caller override, selects repository cwd and emits the only command-specific environment values:
the typed scratch `KUBECONFIG` used by Kind create/delete and nvkind create, plus fixed
`KUBERC=off` for nvkind's nested kubectl calls. The opaque
`BoundedCommand` compiler and total
`CommandSucceeded | CommandFailedFatal | CommandFailedKernel | CommandTimedOut` outcome are the
positive process-execution counterpart to these banned environment reads, whose canonical home is the
[Managed State Transitions](managed_state_transitions.md) doctrine. That same doctrine makes the
harness config swap crash-safe: `withTestHarnessConfig` restores the operator's config through a
`./infernix.dhall.harness-backup` that it reconciles on **entry**, not only through a `finally`
restore a SIGKILL would bypass — so an externally-killed run cannot leave the operator's runtime
config replaced by the test config. The pre-takeover reservation is owner-atomic and rests on the
all-Haskell lifecycle-lock and typed supervision boundary.

One deliberately narrow compatibility input is a `.harness-backup` without a reservation record.
Because that format records no owner identity,
no command-activity proof can be associated with it. Entry reconciliation handles that legacy shape
only while holding the lifecycle lock; every transaction publishes its reservation
before touching config. The compatibility path is tracked explicitly in
[legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md) and is not
part of the v2 quiescence guarantee.

A second source of drift is **hand-maintained `.dhall` schema files** alongside the Haskell
renderers, plus `.dhall` *values* rendered by Helm templating from `chart/values.yaml`. The binary
instead reflects each schema from its decoder type and renders every value, so there is exactly one
source of truth per config (the Haskell type), no
committed schema to drift, and no Dhall inside Helm templates.

## Generated, never tracked

Every `.dhall` is produced by the binary from a Haskell type. There is nothing to hand-edit into
existence and nothing to check in.

| Config | Haskell owner | Created by | Consumed by |
|---|---|---|---|
| **system contract `infernix.dhall`** (substrate mode; the pool graph, each pool carrying the model descriptors it owns) — byte-identical on every machine in the fleet | `Infernix.Substrate` / `Infernix.Models` encoders; defaults in `Infernix.ProjectInit` | `infernix init` (operator) or the test harness (per run) | all service roles preflight through `decodeCompiledRuntimePlanFile`; hidden presentation/generation consumers may project `DemoConfig` |
| **machine contract `infernix-host.dhall`** (tool paths, host context, filesystem, command policies, and the `machine` block: role, member identities, model-cache quota, and the pinned system-contract digest) — per machine | `Infernix.HostConfig` | `infernix init` | host CLI tool resolution and every role's own identity, capacity, and served-model set |
| **cluster config `cluster.dhall`** (in-cluster wiring) | `Infernix.ClusterConfig` (`defaultClusterConfig`) | the binary at `cluster up`, injected into Helm as an `nindent`'d string | pods via `decodeClusterConfigFile` |
| **secrets `InfernixSecrets.dhall`** (paths to secret files, never values) | `Infernix.SecretsConfig` | the binary (host) / `cluster up` (cluster), injected into Helm as a string | secret-path resolution |

### The system contract is shared; the machine contract is not

A fleet is many machines reading one Pulsar topic family, so every fact those machines must agree
on lives in the system contract and **nowhere else**. Topic strings, pool identity, model ids,
download URLs, and model footprints are system facts: a second copy on a second machine is a second
opportunity to disagree, and a disagreement about a topic string is silent — the publisher writes
somewhere nobody reads, and no component errors.

The footprint case is the strongest form of that rule rather than an exception to it, because the
fact is the **artifact plus the execution shape**, not an authored number. A model's memory
requirement is derived from the artifact's own tensor table and from the context length, batch,
generation bound, and load strategy the engine will run under, so there is no per-family constant for
a second copy to drift from — a derived quantity cannot be written down differently on two machines,
which is why moving the requirement into the artifact strengthens the shared-contract rule instead of
weakening it. The execution shape belongs in the system contract for exactly that reason: it is an
input to a requirement every machine must agree on, and it is the same value the engine is started
with. Its counterpart stays off the contract for the mirror-image reason: what a machine can *offer*,
and which enforcement mechanism it can install for each resource, are observed per machine and never
travel — which is why the memory budget is deliberately outside the contract digest below. Canonical
home: [bounded_inference_memory.md](bounded_inference_memory.md).

The rule is the same one that shapes the memory-budget union: **carry exactly
one representative of each fact and derive the rest.** A machine does not restate a topic and does
not restate the pool graph. What a machine authors is only what is true of that machine: which role
it runs, which member identities it may adopt, and how much disk its cache may use. The pools it
serves are *derived* — a pool names its members, so the machine's served set is the pools of the
pinned contract that name one of its members, and a machine whose members no pool names is refused
rather than started with an empty subscription set.

A model belongs to exactly one pool, and the wire says so structurally: a pool carries its own model
descriptors, so there is no second list for it to disagree with. Five disagreement classes — a pool naming a model the catalog does not define, a pool naming a
member that does not exist, a member serving no pool, and a one-sided pool/member link in either
direction — have no representation to write at all.

The pool graph is a `List` of pools keyed by an `id` field rather than a Dhall record keyed by pool
name, and the reason is worth stating rather than leaving to inference: pool ids are derived from
the active substrate's model catalog, so the field set differs per runtime mode, and the substrate
schema is *reflected from the decoder type* (`infernix internal dhall-schema substrate`). A record
whose fields vary per mode is not reflectable, and the map encoding that is — a list of
`{ mapKey, mapValue }` — is the same list with a renamed key field and buys no additional check. So
a machine does not get a Dhall type error for naming an undefined pool; it gets a fail-closed
refusal that names the pool ids the pinned contract defines. The pin below is what makes that
equivalent in practice: the pair was generated together, so the pool set the machine resolves
against is the one it was generated with.

The machine contract pins the system contract it was generated against by content hash, so a machine
cannot be paired with a contract it has never seen. The operational consequence is worth stating
plainly: **when the system contract changes, every machine contract is regenerated**, because the
hash moves. That coupling is the generator's, not the operator's: the same materialization that
writes the system contract re-stamps the machine contract next to it. Both files remain
binary-generated and untracked — the pin is over generated configuration, not over a checked-in
schema, so the zero-version-controlled-`.dhall` rule is untouched.

**The digest covers the contract, not one machine's copy of it.** One deployment legitimately holds
the same contract as more than one payload: the operator's repo-root file names its own absolute
`generatedPath`, and the published cluster mirror is rendered for the pods that mount it. So the
digest is taken over a canonical projection of the facts a fleet must agree on — the substrate mode,
the topic names, the object bucket, and the pool graph with each pool's subscription, members, and
models — with every list sorted. What is deliberately outside it is everything a machine may
legitimately hold differently: file paths, the ConfigMap name, the demo-UI flag, and the inference
memory budget, which is per-machine by construction. Hashing the file bytes instead is not a
theoretical mistake: it made the Apple host engine and the cluster coordinator refuse each other on
a deployment where nothing disagreed.

**Be exact about what the pin buys.** It is *local*: it proves this machine's manifest matches this
machine's copy of the contract, and it cannot see another machine's copy. That is a real reduction
in blast radius — several silent disagreement axes collapse into one — and it is not detection
across a fleet. The check that could detect a fleet disagreement is the third layer: the contract
digest is registered in the Pulsar topic's own properties, and a daemon whose digest disagrees
with the registered value refuses to start, naming both values. The broker is the only place N
machines meet, so that is where the check has to live. It lives in the *topic's* properties rather
than its schema's because a Pulsar schema is keyed by its type and data: re-posting one `BYTES`
schema with different properties is deduplicated into the existing version, so a registrar's
overwrite silently does nothing and a verifier stays pinned to whatever was registered first — across
cluster teardowns, because retained-state replay carries the broker's own storage. Topic properties
are a mutable map, which is what a fact that moves with the fleet's contract needs. Absence is not disagreement: a topic whose
registered schema carries no digest was created by a binary that predates the pin, so the digest is
registered rather than refused.

**One role registers; the rest verify.** The coordinator is the deployment's router, and its
publication is the event that changes what the fleet runs, so it writes the registered digest —
including over a value it disagrees with, because that is exactly what a deliberate contract change
looks like. Every other role verifies, and a verifier that disagrees refuses to start. Without that
split the check is not fail-closed, it is *frozen*: the registered digest is durable broker state
that outlives a cluster, so the first contract change would make every daemon refuse forever against
a value nothing could update. What the split gives up is precise: two coordinators holding different
contracts no longer detect each other, because each would register its own. The deployed topology
has one coordinator, and the fleet case that needs more is owned by the fleet sprint.

The machine contract is a union, not a record of optional fields, because a machine contract without
a pin is exactly the state this doctrine exists to make unrepresentable. `ImageDefault` is the
manifest baked into the Linux launcher image — byte identical in every image, and therefore a
description of no machine at all; it exists so path discovery can classify the execution context
before any machine contract is generated, and a daemon started against it is refused by name.
`Machine` always carries its role, its member identities, its quota, and its pin.

Defaults live in exactly one place — `Infernix.ProjectInit` (the single `init`-and-harness defaults
owner) — so `infernix init` and the test harness share them (DRY). `infernix internal dhall-schema
host|cluster|secrets|substrate` prints the reflected schema for any config on demand; nothing reads
a schema from disk.

### The runtime config is the model source of truth

The set of models in scope for a workload is **the model list in the effective (mounted)
`infernix.dhall`** — not anything compiled into infernix core. The coordinator **eagerly populates
its model cache on startup from that mounted config** (failing fast if there is no config), and the
`warm-model-cache` cluster-up phase blocks until every listed model is staged, so tests never race a
cold cache.

For the demo, the model set is generated from the `matrixRows` table in `src/Infernix/Models.hs` —
but that hardcoding is a **demo-only convenience**: the demo must expose the identical set in its UI,
so it keeps one in-code source feeding both its generated `infernix.dhall` and the frontend. Other
workloads consuming Infernix bring their own source of truth (including dynamic selection /
rotation); infernix core never hardcodes the model set — it stages exactly what the mounted config
lists.

### Baked vs mounted config

The image-baked `infernix.dhall` (written by `infernix init` at docker-build time) lists **no
models** — it exists only so `docker run --rm infernix …` one-shots satisfy the fail-fast rule and
never trigger a download. At deploy, the coordinator's ConfigMap-mounted `infernix.dhall` (the real
model set) is volume-mounted **over** the baked file; only the deployed coordinator stages weights.

## The three cluster-facing config records

### Execution plans are closed and refined

The runtime and host configs feed the closed execution language defined by
[Typed Execution Plan](typed_execution_plan.md). The Haskell core uses indexed ADTs for
resource/enforcer alternatives, and the generated wire carries the memory budget as a proper Dhall
union — `< HostEnforced | SubstrateEnforced | DualEnforced >`, each arm carrying only its own payload
record — so a text discriminator plus zero-filled unused fields is not a representable
shape. Drift is detectable rather than latent: the union's rendered type
annotation is written once and selected by every arm, a unit assertion pins the rendered payload
against the alternatives the reflected decoder expects, and a payload written by a nonunion
generator fails with a diagnostic that names the invalid shape and tells the operator to
regenerate it with `infernix init` (or `infernix test init`) instead of surfacing a bare structural
Dhall type error. Every
enum-like field is a Dhall union rather than `Text` refined after decode — `runtimeMode` and
engine-pool `subscription` on the system contract, `role` and the machine-contract state itself on
the machine contract, plus request-shape `fieldType` — every quantity is `Natural` rather than
`Integer`, and the never-read `edgePort` placeholder is absent from the language. The targeted
compatibility diagnostic covers each invalid text spelling and each retired field, including the
ones this doctrine's contract split moved or derived away: `daemonRole`, the `coordinator` and
`webapp` records, and the `engineMembers` list. See
[typed_execution_plan.md](typed_execution_plan.md) for the full field inventory and the two
mechanical traps the round-trip caught.

The execution-plan decode boundary produces opaque `RawRuntimeConfig`. Haskell compilation
validates model placements, routes, engine bindings, daemon wiring, and admission accounting into
`CompiledRuntimePlan`. Coordinators route only through compiled placements and `CompiledDaemon`
capabilities. Package-owned live observations then verify the named OS enforcer and configured
host/cgroup envelope before refining engine work into `RuntimePlan` / `ExecutableModel`; engine
subscription and launch accept only those refined capabilities.

The same compiled plan owns messaging authority. There is no supported raw topic publisher;
coordinator and engine consumers turn unavailable, empty-model, unknown-model, wrong-route, and
malformed requests into terminal failed results before source removal or acknowledgement.
Model-bootstrap publication requires an opaque plan-derived capability, and the consumer
revalidates model identity, the compiled download URL, and the canonical request timestamp before
side effects. Compilation rejects topic reuse across coordinator-request, result,
model-bootstrap-request, model-bootstrap-ready, and engine-route families. Binary substrate
materialization emits the generated Dhall bytes with explicit UTF-8 encoding.

The generated host manifest also carries command policies:
`retry` is `< Never | Bounded : { attempts : Natural, backoffMicros : Natural } >`,
`failureClass` is `< Fatal | TransientThenFatal | IdempotentAbsence >`, and the
`commandPolicies` record has exactly 36 fields covering Kind, kubectl, Helm, Docker, host probes and
mutations, archive/curl work, GPU userspace synchronization, and image publication. The
hidden-constructor `CommandPolicyPlan` refines that complete record, and each abstract
`ClusterCommand` selects its policy exhaustively through `ClusterOperation`. The command substrate
and every production caller routes through that substrate. Raw runtime-config consumers are confined to hidden
configuration/presentation modules and cannot authorize routing or engine launch.

### Host manifest (`infernix-host.dhall`)

Typed record describing the operator's host environment — absolute **tool paths** for every external
command the project invokes (`docker`, `kubectl`, `helm`, `kind`, `cabal`, `ghc`, `ghcup`, `npm`,
`node`, `python3`, `poetry`, `git`, `tar`, `curl`, `apt-get`, `brew`,
`sudo`, `systemctl`, `mkdir`, `chmod`, `ln`, `install`), **filesystem conventions** (`repoRoot`,
`buildRoot`, `dataRoot`, `runtimeRoot`, `kubeconfigPath`, `secretsRoot`, `homeDirectory`), and the
**host execution context / native architecture**. It also carries the generated 36-field
`commandPolicies` record; test-only kernel probes are deliberately absent from operator
configuration.

Ormolu and HLint run as pinned libraries inside the root Haskell-style test component. The Cabal
manifest printer runs through pinned Cabal 3.16 in a genuinely separate package under
`test/cabal-format/`, because separate test suites in one package still share one solver universe.
The formatter libraries are not host commands and have no
`HostToolPaths` fields.

`protoc` is deliberately absent from the host manifest. Ordinary Haskell builds consume the exact
tracked `src/Proto/` snapshot, Python generation uses its venv's `grpc_tools.protoc` module, and the
standalone pinned compiler exists only inside the Linux image-build regeneration gate.

It carries one record whose values are observed rather than declared: `memory`
(`physicalMemoryMib` / `effectiveMemoryMib`). The observation, its fixed-path probes, and its
fail-closed behavior are owned by
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md); this record is the
input the bounded host build ceiling is derived from
([bounded_host_memory.md](bounded_host_memory.md)), which owns what that ceiling covers and what
admits it.

It additionally carries the **`machine` block** — this machine's role, the engine member identities
it may adopt, its model-cache quota, and the content digest of the system contract it was generated
against. That makes it the machine contract: the one file that differs between two boxes in the same
fleet. Identity is declared and has no default, because a daemon that cannot say which member it is
must refuse to start rather than adopt one; one declared identity needs no selection, and more than
one (the `linux-gpu` shape, one member per framework engine image) requires `--engine-name` to name
one of them. The model-cache quota lives here because it is a machine fact: before it did, the
generated cluster wiring said 64 GiB and the Apple host worker carried its own 32 GiB literal for the
same cache, with nothing connecting the two numbers.

The `role` here is the box's default, not a lock: three roles run from one system contract on the
cluster lane, and `infernix service --role` names which one a process is. What the machine contract
removes is the role's former home on the *system* contract, where a per-box fact had no business
being.

**On a fleet the machine contract is generated per machine, not baked.** The manifest baked into the
Linux launcher image is byte identical in every image, so with more than one engine machine it
collides rather than discriminates. `cluster up` therefore renders one machine contract per fleet
member — the same host manifest with a machine block naming **exactly one** member — publishes them
in a binary-rendered ConfigMap, and mounts each machine's own contract at the repo-root manifest
path. The published system contract is mounted at the repo-root contract path alongside it, so a
fleet pod holds a real generated *pair* and its local pin check and the broker's registered digest
are talking about the same contract. The fleet size itself is declared where the pool graph lives:
`infernix init --engine-machines N` (and `infernix test init --engine-machines N`) expands each
member into `N`, and `N = 1` is the deployed platform's contract unchanged. The placement and
claim mechanisms that make those identities distinct in practice are owned by
[daemon_topology.md](daemon_topology.md).

Written by `infernix init`; the binary decodes it at startup into a `HostConfig` record. See
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md). The retained Apple
materialization command is configured through typed engine-artifact records, never inherited host
process state — see
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

### Cluster config (`cluster.dhall`)

Typed record of in-cluster wiring that must not live in pod-spec `env:` blocks — Pulsar
(HTTP/WS/service URLs, tenant, namespace), MinIO (endpoint, region, presign expiry, buckets),
Keycloak (base URL, realm, client id, JWKS URL), demo backend (bind host, bridge mode, publication
state path), engine (model cache root and quota), coordinator
(control-plane context, daemon location). These are deterministic derived values, so they carry **no
`init`**: the binary renders `cluster.dhall` from `ClusterConfig.defaultClusterConfig` at `cluster
up` and hands the string to Helm, which embeds it verbatim into `ConfigMap/infernix-cluster-config`
(mounted read-only at `/opt/infernix/cluster.dhall`). Helm never parses or templates the Dhall. See
[../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md).

### Secrets (`InfernixSecrets.dhall`)

Typed record naming **file paths** at which secret material lives, never the values:

```dhall
{ minio = { credentialsPath = "/etc/infernix/secrets/minio.json" }
, keycloakAdmin = { credentialsPath = "/etc/infernix/secrets/keycloak-admin.json" }
, keycloakDb = { credentialsPath = "/etc/infernix/secrets/keycloak-db.json" }
}
```

On-cluster the JSON files come from a Kubernetes `Secret` mounted at `/etc/infernix/secrets/`; on
host they live under `./.data/runtime/secrets/` (gitignored). The binary renders both the secrets
Dhall and the credential JSON bodies and injects them into Helm as strings; no secret value is ever
inline in Dhall, injected as an env var, or hand-written into a chart template.

## The bootstrap stage-zero convention

Bootstrap shells are the only operator-facing entry point that runs *before* the Haskell binary is
available. They install host prerequisites, build the launcher image, and delegate every subsequent
command to the binary.

Convention: first line `PATH=/usr/bin:/bin`; repo root from `BASH_SOURCE` (not an env var); operator
home from `/etc/passwd` via `getent` (not `$HOME`); every pre-binary command a hardcoded absolute
path; and once the launcher exists, every operation delegates to the binary
(`"${REPO_ROOT}/.build/infernix" <command>` on Apple; `docker compose … run --rm infernix infernix
<command>` on Linux). The `LAUNCHER_IMAGE=infernix-linux-gpu:local` value the GPU bootstrap sets is
only the Compose image selector — not read by Infernix code, not a config substrate.

The shell never reads a `.dhall` file directly. The Haskell binary is the only Dhall reader.

## Cluster pod contract

Every `chart/templates/deployment-*.yaml` for infernix-owned workloads (coordinator, engine, webapp)
mounts two volumes and carries **no `env:` block**:

- `cluster-config` (from `ConfigMap/infernix-cluster-config`, whose body is the binary-rendered
  `cluster.dhall` string) at `/opt/infernix/cluster.dhall`
- `cluster-secrets` (from `Secret/infernix-cluster-secrets`, binary-rendered) at `/etc/infernix/secrets/`

Each coordinator, engine, and webapp role pod additionally mounts
`ConfigMap/infernix-demo-config` (the binary-rendered runtime `infernix.dhall`, with the real model
set) **over** the image-baked config path. Service startup compiles that Dhall before role-specific
work begins, reads secret files by absolute path, and never consults `env`.

## Third-party-upstream exceptions

The doctrine governs Infernix's own code. Third-party images that consume env vars at startup because
their upstream contract requires it keep their env entries — e.g. **Keycloak** (`KC_DB`, `KC_DB_URL`,
…) read by the upstream image, sourced from a mounted Secret. See [../tools/keycloak.md](../tools/keycloak.md).
The lint gates carry an explicit exception list naming this and any future upstream contract.

## Validation

- `infernix test lint` (the Haskell-style suite) rejects new `lookupEnv` / `getEnv` /
  `proc "<bare-name>"` and `findExecutable` / `findExecutables` discovery outside the lint module's
  own token list and the documented exception list. `infernix lint files` rejects `os.environ` /
  `os.getenv` reads under `python/`, `process.env` reads under `web/`, and any tracked `.dhall`.
- Host-manifest schema tests round-trip all 36 command policies and both proper unions. Subprocess
  refinement tests reject zero/overflowing timeouts, attempts, and backoffs; command compilation
  rejects empty, relative, missing, or nonexecutable paths for every exact domain `HostTool`, while
  commands outside the two fixed Bash pipelines do not acquire a universal Bash dependency.
- `infernix lint chart` rejects any `env:` block in the infernix-owned
  `deployment-{coordinator,engine,demo}.yaml`, and any Dhall `let …`/schema body inside a chart
  template (Helm must only `nindent` a binary-produced payload string).
- `infernix lint docs` / `infernix docs check` keep the governed docs (this doctrine, `no_env_vars.md`,
  the manifest specs, tool docs, plan docs) in the machine lint set, reject retired-doctrine
  language, and — for the Dhall schemas — assert each reflects to a non-empty expression (there is no
  tracked `.dhall` to diff against). The unit suite additionally round-trips a default value of each
  config through encode → decode.
- A tree scan asserts **zero tracked `.dhall`** (`git ls-files '*.dhall'` is empty).
- End-to-end: `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh up` (empty starting env) reaches steady
  state, proving the contract holds when the operator's shell starts with no env vars at all.

## Cross-References

- [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md) — host-manifest schema spec.
- [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md) — cluster-config record + ConfigMap/Secret mount contract.
- [../development/no_env_vars.md](../development/no_env_vars.md) — developer-facing rules and lint gates.
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md) Sections T and U.
- [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md) for the retirement ledger.
- [Managed State Transitions](managed_state_transitions.md) — typed `SubprocessEnv` / `CommandOutcome`
  process-execution counterpart to the banned environment reads.
