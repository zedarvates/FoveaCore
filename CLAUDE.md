# FoveaEngine contributor guide

Read `AGENTS.md` first; it is the authoritative project policy.

## Local workflow

- Prefix shell commands with `rtk`.
- Open the project with Godot 4.7-dev5 Mono (or a compatible 4.7 build).
- Validate script loading with the headless Godot editor command before release.
- Run `python addons/tools/test_validation_tools.py` after changing validation tools.
- Run the project checkup after each component update.

## Engineering constraints

- Use strictly typed GDScript and English comments/documentation.
- Keep `FoveaCoreManager` as a lightweight autoload orchestrator; put domain logic in its subsystems.
- Defer heavy work from `_ready()`.
- Guard RenderingDevice and GPU readback paths for null/headless/Compatibility modes.
- Use bulk MultiMesh updates; avoid per-instance update loops.
- Validate `.fovea` input extension and `FOVEA_3D` header before parsing.
- Keep clay deformation reversible from cached original transforms.

## Release policy

- Do not claim a backend is production-ready without CI and target-machine validation.
- Keep commits focused. Do not commit local paths, model weights, generated artifacts, or personal settings.
