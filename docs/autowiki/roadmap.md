# FoveaEngine Evidence Roadmap

This roadmap prioritizes contract correctness and measurable validation over feature-count claims.

## P1 — Correctness and compatibility

### 1. Freeze and test the `.fovea` contract

- [x] Choose the canonical v2 identity and record layout.
- [x] Reclassify the incompatible 8-byte design as a v3 research proposal.
- [x] Add cross-language golden fixtures and corrupt-input tests.
- [x] Assert semantic interpretation of every 16-byte splat field.
- Run the direct 24-byte instanced GPU readback test under the declared Godot 4.7 CI baseline, then inspect publication-texture parity. A separate non-GPU source-contract suite covers shader/layout drift during the hardware-blocked interval.
- Keep process- and network-dependent suites marked `REQUIRES_INTEGRATION` so the hard-fail `nogpu` runner remains deterministic.
- **Exit:** all supported reader/writer combinations pass on the Godot 4.7+ baseline and the conflicting plan is superseded or relabeled.

### 2. Reconcile public API documentation

- [x] Compare `docs/developer_reference.md` with current stable-node, autoload, and reconstruction script signals and methods.
- [x] Remove absent signatures and distinguish autoload identities from backing `class_name` values.
- [x] Add a source-extracted, non-GPU signature drift check.
- **Exit reached for the scoped public surfaces:** every active public method and signal in the guarded sources is documented; known obsolete signatures are rejected. Full reference generation remains P3 work.

### 3. Normalize capability status

- Reconcile `ROADMAP.md`, historical audits, plans, and `docs/feature-status.md`.
- Require evidence state and validation date for performance/readiness claims.
- **Exit:** release-facing docs contain no unqualified production claims for hardware-dependent paths.

## P2 — Validation depth

### 4. Establish GPU and XR baselines

- Select representative desktop and headset fixtures.
- Record frame-time percentiles, RAM/VRAM, image quality, renderer, and driver.
- Promote informative CI checks only after stable hardware baselines exist.
- **Exit:** reproducible baseline reports for core assets and supported renderers.

### 5. Make audit output machine-readable

- Adopt or revise the proposed agent JSON envelope.
- Add schemas, parsers, fixtures, and severity/evidence validation.
- **Exit:** Wiki, audit, fix, and performance runs produce schema-valid records.

### 6. Clarify native packaging

- Preserve the accepted Rust-packaged/C++-experimental artifact ownership and validate the updated C++ CI job.
- Detect collisions and verify binary provenance in CI.
- **Exit:** one unambiguous packaged native artifact per target, with any opt-in C++ package covered by install and load tests.

## P3 — Automation and ergonomics

### 7. Generate the API reference

- Extract Godot script classes, signals, exports, and public methods.
- Fail CI on stale generated reference output.

### 8. Add Wiki consistency checks

- Validate links, evidence-state vocabulary, decision IDs, and referenced paths.
- Track unresolved conflicts as a numeric metric for future autoresearch.

### 9. Build bounded research runners

- Add experiment manifests with metrics, commands, scope, budget, and baseline.
- Preserve results without allowing destructive rollback of unrelated work.
