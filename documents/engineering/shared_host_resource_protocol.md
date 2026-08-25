# Shared Host Resource Protocol

**Status**: Draft
**Referenced by**: [Documentation index](../README.md)

> **Purpose**: Record how Infernix would participate in the shared host claim ledger installed on a
> development machine, and the exact seam it would attach to.
> **Read this if**: you are deciding whether a toolchain spawn, an engine launch, or a cluster operation may
> proceed on a machine shared with another project.

**Not adopted.** No Infernix code reads or writes the ledger, no command depends on it, and no phase owns the
work. The ledger is host configuration owned by the machine's operator; its authority is the installed root
and the `spec-version` that root carries, never a copy of a document in any repository, including this one.
This file records only what Infernix would do, so no dependency on another project is created by writing it.

## Contents

- [1. The problem here](#1-the-problem-here)
- [2. What Infernix would claim](#2-what-infernix-would-claim)
- [3. Where it would attach](#3-where-it-would-attach)
- [4. The rendezvous question](#4-the-rendezvous-question)
- [5. Coverage, which does not cross the boundary](#5-coverage-which-does-not-cross-the-boundary)
- [6. Open before adoption](#6-open-before-adoption)

## 1. The problem here

Both existing exclusion mechanisms already say what they are not. Toolchain host admission is an observation
at an instant rather than a lease, which is why the child boundary re-takes it instead of trusting the answer
taken at mint. The engine lock is `runtimeRoot </> "engine.lock"`, and `runtimeRoot` resolves against the
repository, so it cannot exclude a second checkout.

The source states the consequence directly: the lifecycle lock, the harness reservation, and the persisted
state are all repository-local, while the Kind cluster they claim to protect is machine-global. A ledger
gives those three a machine-global object to name.

## 2. What Infernix would claim

- A `Transient` claim for a toolchain invocation, charging host memory and processor time. `Transient` is
  honest for supervised foreground compilation: when it dies, the operating system has reclaimed what was
  charged.
- A claim holding the whole-device domain for a Metal or CUDA execution, so two participants cannot select
  the same physical accelerator.
- A `Persistent` claim for a retained cluster and for the engine process, if either is claimed at all. The
  engine claim is the candidate replacement for the checkout-local `engine.lock` — a replacement, not a second
  authority beside it with no declared precedence.

One property must survive the adapter: one engine process per physical machine is an Infernix correctness
rule, not operator policy. The ledger's slot count is policy and must never be read as permission to run a
second engine that independently admits against the same machine.

Refusal outcomes must stay distinct, because delivery semantics depend on it. A contended claim is transient
and must not be published as a model-capacity failure; a request that cannot fit is terminal and must not be
retried as though it were merely contended.

## 3. Where it would attach

At the existing toolchain host-admission seam, which already observes the machine and already refuses at the
right moment. Participation replaces an instantaneous observation with a claim that persists for the work,
which is precisely the gap that seam documents about itself.

The claim is an input to the existing typed authorities, never a replacement for them. Plan derivation, live
refinement, ceiling installation, observer readiness, and terminal-result behaviour keep their evidence; the
claim only establishes that the machine's capacity was not already spent.

## 4. The rendezvous question

This is the hardest part of adoption here and is unresolved.

Supported Linux commands run through `docker compose run --rm`, one fresh container per invocation, and there
is no supported Linux host-native command path. On Apple hosts, `linux-cpu` work runs in the Colima Linux VM
while control-plane and Metal execution are host-native.

A container coordinates with the host only if the host root is bind-mounted at the same path inside it. A
guest-local file with that name is a different object and coordinates nothing. Adding one mount alongside the
repository and Docker-socket mounts is small; deciding whether an Apple-hosted Linux container claims against
the host machine or believes itself to be a separate one is not, and that decision has to be made before any
claim from inside a container means anything.

Until it is settled, participation is honest only for host-native invocations.

## 5. Coverage, which does not cross the boundary

Infernix's layered host-memory enforcement is the reason a single strength label cannot describe a mechanism.
A data-segment ceiling installed before the engine's first instruction covers private writable mappings and
cannot be raised by the process it binds; a fixed-cadence observer covers the shared and pinned memory that
ceiling does not charge. Both are required, and calling the pair either "hard" or "reactive" misdescribes it.

Nothing about that is shared. A claim states demand; the walls a participant applies to itself are its own,
and no other participant needs to agree on them. The coverage model belongs in this repository's own
enforcement doctrine.

## 6. Open before adoption

- No phase or sprint owns the record reader, the adapter, or the seam change. The cross-checkout defect the
  cluster source names already has an owner; a machine-global object is what that work needs.
- The container and VM rendezvous above.
- Release evidence. A claim is only as good as its release: the engine and cluster paths must gate release on
  their existing teardown evidence, and hold rather than release when that evidence is partial.
