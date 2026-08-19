# FoveaEngine — Architecture & Addon Layout

> Status: living document · Last updated 2026-06-13 · See [PLAN_VOLINGA_PARITY.md](../PLAN_VOLINGA_PARITY.md) and [plans/PHASE0_FONDATION_TASKS.md](../plans/PHASE0_FONDATION_TASKS.md).

## The shipped product: `addons/foveacore`

**`foveacore` (GDScript + Rust GDExtension) is the canonical, supported product.**
It is the addon enabled in `project.godot` and the one published in releases.

| Layer | Where | Language |
|---|---|---|
| Public API | `scripts/fovea_splat_3d.gd` ([FoveaSplat3D]), `scripts/fovea_asset.gd` ([FoveaAsset]) | GDScript |
| Rendering / culling / sort | `scripts/advanced/`, `shaders/`, Rust crate `rust/` | GDScript + GLSL + Rust |
| Reconstruction (StudioTo3D) | `scripts/reconstruction/` + Python bridges | GDScript + Python |
| Native fast path | `rust/` → `gdextension/bin/` | Rust (godot-rust/gdext) |

The single public node a game developer needs is **`FoveaSplat3D`**: drop it in a
scene, assign a `.fovea` / `.ply` / `.splat` source, done. Everything advanced is
reachable via `FoveaSplat3D.get_advanced()` (the internal `FoveaSplattable`).
The planned `.spz` decoder is not part of the public file picker until it exists.

## Experimental tools: `addons/fovea_labs`

Experimental / niche creation-dialog types (VR brushes, splat cloth, decals,
multiplayer sync, neural style, segmentation, clay deformer…) are registered by a
**separate, optional `fovea_labs` plugin**. Disabling it never breaks code: the
underlying scripts keep their global `class_name` and remain importable — only the
"Create Node" aliases disappear. This keeps `foveacore`'s registered surface down
to its 3 public types.

## The C# addon: `addons/fovea_engine` — NOT the shipped product (decision A4)

`addons/fovea_engine` is a **parallel C# implementation** ("Fovea Gaussian Splat
Suite"). As of Phase 0 it is **not enabled** as an editor plugin in
`project.godot` and is **not part of the FoveaEngine Core deliverable**.

**Decision (Phase 0, task A4):** ship and support a single addon, `foveacore`.
The C# `fovea_engine` addon is treated as an optional / experimental alternative:

- It is **not** activated by default and **not** included in the release zip
  (release packaging = `addons/foveacore/` only).
- It still compiles via `FoveaEngine.csproj` (the CI `dotnet-build` job keeps it
  honest) but carries no support guarantee.
- Future C# interop should take the form of **thin bindings over `foveacore`**,
  not a competing renderer. Anything that duplicates `foveacore` functionality is
  a candidate for removal once bindings exist.

Rationale: two full renderers double the maintenance and test surface and split
the "studio-grade stability" promise. One canonical pipeline, optional bindings.

## Plugin registration (table-driven)

`foveacore/plugin.gd` registers autoloads and custom types from two `const`
tables (`AUTOLOADS`, `CUSTOM_TYPES`) walked symmetrically in
`_enter_tree`/`_exit_tree`, so a registration can never be left without its
matching cleanup. `fovea_labs/plugin.gd` follows the same pattern.

## Embedded 3DGS Trainer Backend Decision (Phase 1, Chantier G)

To support one-click, zero-terminal training within the Godot editor, we use a uniform `FoveaTrainerBackend` interface.

1. **Default/Primary Backend**: [Brush](https://github.com/ArthurBrussee/brush)
   - **Tech stack**: Rust + WGPU.
   - **Rationale**: Written in Rust, matching our core extension technology. It uses WGPU/Vulkan for compute shader training, which runs natively on desktop platforms without needing a Python runtime. This allows ultra-fast training directly on the GPU.
2. **Fallback Backend**: Python `gsplat` / `splatfacto`
   - **Tech stack**: Python Standalone + PyTorch + `gsplat`.
   - **Rationale**: If the host machine lacks Vulkan/WGPU support or encounters driver compatibility errors, we fall back to the Python environment installed in `user://fovea_tools/python/`. The Python backend runs the training process via subprocesses.

## Release packaging (target, Phase 0 task D2)

The release zip contains exactly: `addons/foveacore/` (with `gdextension/bin/`
populated for all platforms) + `LICENSE` + `README`. `fovea_labs` ships
alongside as an optional extra; `fovea_engine` (C#) does not ship.
