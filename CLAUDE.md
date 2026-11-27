# CLAUDE.md

**Status**: Governed entry document
**Supersedes**: older root-level workflow duplication for LLM coding assistants
**Canonical homes**: [documents/README.md](documents/README.md), [documents/documentation_standards.md](documents/documentation_standards.md), [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md), [documents/development/local_dev.md](documents/development/local_dev.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: Provide a thin automation-oriented entry document that points Claude-style agents at
> the canonical workflow and implementation-status docs.

Instructions for Claude and other LLM-based coding assistants working in this repository.

Read first:

- [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md)
- [documents/development/local_dev.md](documents/development/local_dev.md)
- [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)
- [documents/development/no_env_vars.md](documents/development/no_env_vars.md)
- [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- [documents/architecture/bounded_inference_memory.md](documents/architecture/bounded_inference_memory.md)
- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

## Workflow Authority

Read and follow the complete
[Non-Negotiable Rules](documents/development/assistant_workflow.md#non-negotiable-rules)
in the canonical assistant workflow before making changes. That document is the sole rule list.
Its [validation handoff requirements](documents/development/assistant_workflow.md#validation-before-handoff)
cover validation evidence and reporting unavailable gates.

## Scope

The canonical assistant workflow lives in
[documents/development/assistant_workflow.md](documents/development/assistant_workflow.md). This
root file is only the entry point. Supported stage-0 host bootstrap entrypoints live under
`bootstrap/` and are documented in [README.md](README.md) and
[documents/development/local_dev.md](documents/development/local_dev.md). Those bootstrap
entrypoints are restartable prerequisite reconcilers: they verify same-process tool activation
before continuing, stop at explicit rerun boundaries when a new shell or reboot is required, and
delegate cluster lifecycle, Kubernetes manifests, cluster workload image pulls, registry
publication, validation, and teardown behavior to the `infernix` binary.

Agents are responsible for rebuilding the relevant package or image as appropriate before testing,
so the code under test reflects the intended changes. Stop the existing Colima VM when host-only
tests need its memory; preserve running workloads and retained data through the supported lifecycle
before stopping it, and restart the VM when Docker-backed work resumes. A change in VM allocation
may require regenerating the host build-memory plan before governed host tests; preserve existing
configuration when doing so.

Monitor disk headroom during Docker-backed work. As builds and validation runs proceed, remove
obsolete images and build-cache entries created by the current work, including after failures,
so they do not accumulate and exhaust the host. Keep images needed by active work and preserve
unrelated workloads, images, volumes, and retained data.
