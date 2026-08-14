<div align="center">
  <img src="../../icon.svg" alt="FoveaEngine logo" width="88" />

  <h1>FoveaEngine Autowiki</h1>
  <p><strong>Repository-grounded knowledge, validation records, conflicts, and adoption gates.</strong></p>
  <p><a href="../../README.md">Project overview</a> · <a href="../feature-status.md">Feature status</a> · <a href="tests/README.md">Validation matrix</a> · <a href="roadmap.md">Roadmap</a></p>
</div>

This directory is the evidence-based knowledge index for FoveaEngine. It describes the current repository, records disagreements without hiding them, and points to executable sources instead of duplicating large historical plans.

![Bonsai Gaussian-splat fixture rendered by FoveaEngine in Godot](../images/foveaengine-bonsai-runtime.png)

<p align="center"><sub>Current PLY runtime evidence: <code>demo_bonsai.ply</code> loaded through <code>FoveaSplat3D</code> in Godot 4.7.dev5, Forward+, and D3D12 desktop mode. This is a compatibility capture, not a benchmark.</sub></p>

## Evidence policy

| State | Meaning |
| --- | --- |
| **VALIDATED** | Reproduced in the current task with a recorded command, result, environment, and date. |
| **VALIDATED_WITH_VERSION_GAP** | Reproduced, but with a Godot version below the declared project baseline. |
| **IMPLEMENTED_UNVALIDATED** | An executable path exists, but this task did not reproduce it. |
| **EXPERIMENTAL** | Implemented but unstable, hardware-dependent, or not release-certified. |
| **PROPOSED** | Design or roadmap only. |
| **CONFLICT** | Current sources disagree and require an explicit decision or compatibility test. |
| **FAILED** | The scoped path executed, but a required gate did not pass. |
| **BLOCKED** | The required environment, dependency, or compatible contract is unavailable. |

When sources disagree, use this precedence: implementation → current reproducible result → CI → release documentation → plans and historical audits.

## Current evidence snapshot

| Surface | State | Current evidence |
| --- | --- | --- |
| PLY runtime through `FoveaSplat3D` | **VALIDATED** | The 12,473-splat bonsai and 8,000-splat reference fixtures produced D3D12 captures without script, parse, or load errors. |
| `.splat` parser and router | **VALIDATED** | Godot 4.7.dev5 passed 14/14 assertions over a deterministic 256-splat round-trip and negative inputs. |
| `.spz` decoder | **PROPOSED** | Planned input is rejected and no longer appears in the public file picker until a decoder and fixtures exist. |
| `.fovea` v2 structure and packed records | **VALIDATED** | Godot 4.7.dev5 passed 28 canonical, packed-record, corrupt-input, and Rust-fixture assertions; Rust passed five tests and reproduced the 208-byte fixture exactly. |
| Native `.fovea` runtime rendering | **EXPERIMENTAL** | A deterministic CPU passthrough produced a framed green/brown 800×600 D3D12 capture from 12,473 records (11,808 after cleaning). Palette, AABB, and linear covariance handling pass their source contract; a synthetic two-instance GPU layout/readback passes, while representative native parity and acceleration remain open. |
| GPU depth sorter | **EXPERIMENTAL** | The prepared-index PLY capture detected an incomplete padded permutation and failed closed to an exact 12,473-splat CPU sort. |
| C++ GDExtension | **CONFLICT** | CI compiles it, but its `foveacore_init` symbol and output filename conflict with the Rust runtime descriptor. |
| Transparency visual harness | **FAILED** | It reaches its textual summary but records hundreds of errors and marks scenarios passed without an oracle. |
| Experimental demo scenes | **PROPOSED** | Eight named `.tscn` files contain only empty `Node3D` roots; no selector hub is present. |

## Knowledge map

| Area | Canonical page | Purpose |
| --- | --- | --- |
| Engine contract | [spec.md](spec.md) | Goals, constraints, APIs, formats, tests, risks, and acceptance criteria. |
| Architecture | [architecture.md](architecture.md) | Product boundary, components, and end-to-end flows. |
| FoveaCore | [fovea-core/README.md](fovea-core/README.md) | Splat loading, rendering, native paths, shaders, and compression. |
| Godot | [godot/README.md](godot/README.md) | Nodes, autoloads, plugins, VR, interactions, and editor behavior. |
| Pipeline | [pipeline/README.md](pipeline/README.md) | Reconstruction, build, CI, audit, logs, metrics, and interchange. |
| Agents | [agents/README.md](agents/README.md) | Proposed audit, fix, performance, and Wiki agent contracts. |
| Validation | [tests/README.md](tests/README.md) | Automated, GPU, visual, VR, and performance test surfaces. |
| Research | [research/README.md](research/README.md) | Hypotheses, baselines, experiments, and retained conclusions. |
| Decisions | [design-decisions.md](design-decisions.md) | Accepted and pending architecture decisions. |
| Priorities | [roadmap.md](roadmap.md) | Evidence-based work ordered by exit criteria. |
| Agent prompt | [PROMPT.md](PROMPT.md) | Reusable operating contract for future Autowiki tasks. |

## Update protocol

1. Inspect Git status and preserve unrelated changes.
2. Trace the affected implementation, tests, CI, and documentation.
3. Update only impacted pages and attach an evidence state to capability claims.
4. Record cross-cutting choices in `design-decisions.md` and measurable experiments in `research/`.
5. Run documentation checks plus the smallest relevant executable validation.

## Initial compilation

The initial compilation on 2026-07-16 found a working FoveaCore-oriented project structure and two high-value documentation conflicts:

- **RESOLVED:** `.fovea` v2 is frozen as `FOVEA_3D`, a 72-byte header, and 16-byte splat records. `plans/gaussian_compression_spec.md` is now explicitly a future v3 research proposal.
- **CONFLICT:** `docs/developer_reference.md` documents manager and reconstruction APIs that do not match the current method and signal signatures.

These conflicts are tracked in the [roadmap](roadmap.md) and are not treated as implemented capabilities.
