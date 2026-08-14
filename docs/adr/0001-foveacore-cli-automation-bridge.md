# ADR-0001: Keep Fovea automation provider-neutral and versioned

**Status:** Accepted
**Date:** 2026-08-11
**Deciders:** FoveaEngine maintainers

## Context

Local coding agents need to inspect and modify Godot scenes containing Gaussian
splats. FoveaCore already owns the public `FoveaSplat3D` node and asset-loading
rules, while the Ultimate Odycer runtime CLI already owns authenticated loopback
transport and capability gates. Coupling FoveaCore directly to one CLI or LLM
provider would duplicate security controls and make the public addon depend on
private project infrastructure.

## Decision

FoveaCore exposes a small GDScript automation contract at
`scripts/integration/fovea_cli_bridge.gd`. Contract version 1 supports bounded
status, validation, and unsaved node creation. It starts no listener, writes no
files, and calls no model provider.

A compatible control tool discovers the contract at runtime and retains
responsibility for authentication, mutation approval, transport limits, diffs,
and explicit persistence. FoveaCore retains responsibility for public-node
construction, project-path confinement, supported formats, load-result checks,
and Fovea-specific validation.

## Options considered

### Embed a network CLI in FoveaCore

Rejected because it would duplicate authentication, ports, request limits, and
security maintenance inside a rendering addon.

### Add Fovea logic directly to one external CLI

Rejected because Fovea's format and runtime rules would drift outside the
canonical addon and other tools could not reuse them safely.

### Versioned provider-neutral bridge

Accepted because the dependency remains optional in both directions, the
security boundary is explicit, and each repository can test its own contract.

## Consequences

- FoveaCore remains usable without a CLI or LLM.
- Gemini, OpenAI, Claude, and local-model adapters can plan the same deterministic operations.
- Adding a splat mutates only the live scene; saving requires a separate explicit gate.
- Contract-breaking changes require a new contract version.
- Headless bridge success does not certify native acceleration, visual quality, GPU performance, or OpenXR behavior.
