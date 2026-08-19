# FoveaEngine Pipelines

## Reconstruction

**EXPERIMENTAL:** the reconstruction path coordinates `StudioProcessor`, `ReconstructionManager`, `ReconstructionBackend`, session resources, external commands, and result import.

Backends include the classical FFmpeg/COLMAP path plus optional bridge entry points. Every backend must distinguish:

- dependency unavailable;
- dry-run validation;
- command started;
- progress/log output;
- timeout, cancellation, out-of-memory, or process failure;
- output validation;
- successful import.

## Build and CI

`.github/workflows/ci.yml` defines these validation surfaces:

- GDScript parsing;
- Python bridge syntax and local validation-tool tests;
- C# build and test host;
- Godot import and compile check;
- non-GPU hard-fail tests;
- informative GPU tests;
- renderer startup smoke matrix;
- visual-regression bootstrap;
- Rust build, tests, and lints;
- Windows C++ GDExtension build.

Configured jobs are **IMPLEMENTED_UNVALIDATED** until a current run is inspected.

The C++ job remains a standalone Windows release surface. It now writes `gdextension/bin/foveacore_cpp.dll` with the `foveacore_cpp_init` entry point, while the active release descriptor continues to package Rust `gdext_rust_init` as `foveacore.dll`. A local explicit descriptor smoke test loads and instantiates `FoveaRenderer`; the updated remote CI job, cross-platform builds, and release packaging remain separate gates.

## Audit

Repository-local validation utilities live under `addons/tools/`. Historical audit prose is lower authority than current code, tests, and `docs/feature-status.md`.

An audit finding must contain priority, evidence state, file path, observed behavior, expected contract, reproduction or inspection method, and recommended verification.

## Logs and metrics

Runtime progress currently uses Godot signals and captured process output. The following fields should be present before logs are treated as a stable machine interface:

- schema version and run ID;
- timestamp and environment;
- component and operation;
- severity and evidence state;
- progress and duration;
- input/output identifiers without secrets;
- metric name, value, unit, and baseline;
- error code, message, and recoverability.

The JSON contract remains **PROPOSED** until a schema and consumer test are committed.
