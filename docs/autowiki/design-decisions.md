# FoveaEngine Design Decisions

## Accepted

### DD-001 — Canonical product path

- **Decision:** `addons/foveacore` is the canonical product path. Experimental plugins and the parallel C# surface do not redefine the shipped renderer.
- **Evidence state:** IMPLEMENTED_UNVALIDATED
- **Evidence:** `docs/ARCHITECTURE.md`, `addons/foveacore/plugin.gd`, `project.godot`, `.github/workflows/ci.yml`.

### DD-002 — Evidence beats completion prose

- **Decision:** implementation and current reproducible validation outrank roadmaps, checkboxes, and historical audits.
- **Reason:** several historical documents claim completion beyond the conservative release-facing status.
- **Consequence:** disagreements remain visible as **CONFLICT** until resolved.

### DD-003 — Targeted Wiki compilation

- **Decision:** maintain canonical knowledge under `docs/autowiki/` and update only pages affected by a task.
- **Reason:** rewriting every requested topic on every response would create duplication and drift.

### DD-004 — Guarded autoresearch

- **Decision:** no autonomous experiment loop without a numeric metric, executable measurement, explicit scope, constraints, budget, and baseline.
- **Reason:** unmeasured iteration cannot justify keeping a change and unsafe Git rollback can destroy unrelated work.

### DD-005 — `.fovea` format identity

- **Decision:** freeze `FOVEA_3D`, version 2, a 72-byte little-endian header, and a 16-byte splat record as the current contract.
- **Decision:** reclassify the 8-byte design as a future v3 research proposal with a distinct identity.
- **Evidence:** shared GDScript constants, GDScript reader/writer checks, Rust little-endian header tests, and the canonical format specification.

### DD-006 — Native artifact ownership

- **Decision:** Rust owns the canonical packaged `foveacore` artifact and active descriptor on every current release target.
- **Decision:** C++ remains an opt-in experimental Windows target with `foveacore_cpp_init`, `foveacore_cpp.dll`, and a non-active descriptor template.
- **Evidence state:** VALIDATED locally on Windows; remote CI and other platforms remain open.
- **Evidence:** 14/14 ownership assertions, successful SCons/MSVC release build, distinct PE exports, successful Godot registration/instantiation smoke, and a missing-binary negative control.

## Pending

### DD-007 — Agent interchange schema

- **State:** PROPOSED
- **Question:** whether the run envelope in `agents/README.md` becomes the canonical JSON contract.
- **Exit criterion:** JSON Schema, parser, fixtures, permission enforcement, and integration tests.
