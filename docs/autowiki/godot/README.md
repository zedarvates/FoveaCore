<div align="center">
  <img src="../../../icon.svg" alt="FoveaEngine logo" width="88" />

  <h1>FoveaEngine for Godot</h1>
  <p><strong>Load, inspect, and render Gaussian splats through a Godot-native workflow.</strong></p>
  <p><a href="../../../README.md">Project overview</a> · <a href="../README.md">Autowiki</a> · <a href="../../feature-status.md">Feature status</a> · <a href="../tests/README.md">Validation matrix</a></p>
</div>

<table>
  <tr>
    <td width="50%"><img src="../../images/studio-to-3d-editor.png" alt="StudioTo3D dock in the Godot editor" /></td>
    <td width="50%"><img src="../../images/foveaengine-bonsai-runtime.png" alt="Bonsai Gaussian splat rendered by FoveaEngine in Godot" /></td>
  </tr>
  <tr>
    <td align="center"><sub>StudioTo3D editor surface. The interface is implemented; this image does not prove an end-to-end reconstruction.</sub></td>
    <td align="center"><sub>Validated PLY compatibility capture: 12,473 splats in Godot 4.7.dev5, Forward+, and D3D12 desktop mode.</sub></td>
  </tr>
</table>

> [!IMPORTANT]
> The runtime image is compatibility evidence, not an FPS, image-quality, OpenXR, or release-certification benchmark. See the [validation matrix](../tests/README.md) for the recorded environment and retained failures.

## Current Godot surface

| Capability | Evidence state | Current result |
| --- | --- | --- |
| `FoveaSplat3D` with PLY fixtures | **VALIDATED** | The 12,473-splat bonsai and 8,000-splat reference fixtures produced desktop D3D12 captures without script, parse, or load errors. |
| `.splat` parser and router | **VALIDATED** | Godot 4.7.dev5 passed 14/14 assertions over 256 deterministic records and negative inputs; rendering is not yet benchmarked. |
| `.spz` decoder | **PROPOSED** | Planned files are rejected and no longer advertised by the public picker. |
| Desktop fallback without OpenXR | **VALIDATED** | The PLY capture path completed without a connected headset. |
| `.fovea` v2 structure | **VALIDATED** | Godot 4.7.dev5 passed 28 assertions covering canonical fields, packed records, corrupt inputs, and the Rust-generated fixture. |
| Native `.fovea` rendering | **EXPERIMENTAL** | Godot 4.7.dev5/D3D12 produced a framed green/brown capture from 12,473 canonical records (11,808 after cleaning) through the default CPU passthrough. A synthetic two-instance GPU layout/readback passes; representative native parity and acceleration remain open. |
| GPU depth sorting | **EXPERIMENTAL** | An incomplete padded GPU permutation is rejected and falls back to the exact 12,473-splat CPU sorter. |
| StudioTo3D editor dock | **IMPLEMENTED_UNVALIDATED** | The editor surface exists, but reconstruction still depends on separately installed backends and representative input. |
| OpenXR, eye tracking, and foveation | **EXPERIMENTAL** | Desktop fallback exists; headset performance and tracking acceptance remain open. |

Evidence-state definitions live in the [Autowiki index](../README.md#evidence-policy).

## Minimal scene setup

The development project targets Godot 4.7 with C# and Forward+. Enable the FoveaCore plugin, then add a `FoveaSplat3D` node in the editor and assign its `source_path`. The checked-in PLY fixture can also be loaded from GDScript:

```gdscript
var splat := FoveaSplat3D.new()
splat.source_path = "res://test/demo_bonsai.ply"
splat.quality_preset = FoveaSplat3D.QualityPreset.BALANCED
add_child(splat)
```

`FoveaSplat3D` is the stable public entry point. Advanced styles, overrides, instancing, and morph operations remain on its internal `FoveaSplattable` delegate, available after the node is ready through `get_advanced()`.

## Plugin surface

The FoveaCore editor plugin registers a deliberately small public surface:

| Surface | Registered members |
| --- | --- |
| Custom nodes and resources | `FoveaSplat3D`, `FoveaAsset`, `FoveaSplattable` |
| Autoloads | `FoveaCoreManager`, `ReconstructionManager`, `EyeTrackingBridge` |
| Editor tools | StudioTo3D dock, splat inspector, 3D gizmo, context actions, and file picker |
| Resource integration | `.fovea` loader and saver |

The `fovea_labs` plugin owns experimental brushes, cloth, decals, multiplayer, neural, and related tooling so the main addon can keep a smaller public contract.

## Node lifecycle contract

New integrations must:

- type variables, arguments, and return values;
- avoid heavy synchronous work in `_ready()`;
- make editor actions undoable when they mutate scenes;
- tolerate missing native binaries and missing OpenXR;
- keep editor-only services out of runtime exports where possible;
- avoid assuming Forward+ resources exist in compatibility or headless modes;
- treat empty or malformed assets as failures instead of successful empty scenes.

## VR and interaction

`FoveaVRSubsystem` initializes OpenXR and falls back to desktop when the interface is unavailable. `FoveaFoveatedSubsystem` supplies a camera-forward gaze fallback when eye tracking is absent.

VR acceptance still requires a real headset run recording the runtime, renderer, refresh rate, average and percentile frame time, tracking source, thermal state, and representative splat asset. A desktop fallback capture does not close that gate.

## Editor and reconstruction boundary

The StudioTo3D dock coordinates extraction, reconstruction backends, progress, logs, and result import. FFmpeg, COLMAP, WorldMirror, DiffSynth, and other optional backends remain external dependencies and must fail explicitly when unavailable.

Collision generation, conversion, and external reconstruction operations must run deferred or asynchronously, report failure, and leave the viewport responsive.
