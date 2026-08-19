<div align="center">
  <img src="../../icon.svg" alt="FoveaEngine logo" width="96" />

  <h1>FoveaCore</h1>
  <p><strong>The Godot addon behind FoveaEngine's Gaussian-splat loading, rendering, editor, reconstruction, and XR surfaces.</strong></p>
  <p><a href="../../README.md">Project overview</a> · <a href="../../docs/autowiki/godot/README.md">Godot guide</a> · <a href="../../docs/feature-status.md">Feature status</a> · <a href="../../docs/autowiki/tests/README.md">Validation matrix</a></p>
</div>

<table>
  <tr>
    <td width="50%"><img src="../../docs/images/studio-to-3d-editor.png" alt="StudioTo3D dock in the Godot editor" /></td>
    <td width="50%"><img src="../../docs/images/foveaengine-bonsai-runtime.png" alt="Bonsai Gaussian splat rendered by FoveaCore in Godot" /></td>
  </tr>
  <tr>
    <td align="center"><sub>StudioTo3D editor surface. External reconstruction backends require separate installation and validation.</sub></td>
    <td align="center"><sub>Validated PLY compatibility capture: 12,473 splats in Godot 4.7.dev5, Forward+, and D3D12 desktop mode.</sub></td>
  </tr>
</table>

FoveaCore exposes a small public Godot API through `FoveaSplat3D`, while advanced rendering, native acceleration, reconstruction, editing, animation, and XR behavior remain in decoupled subsystems.

> [!IMPORTANT]
> This addon is under active development. The screenshots demonstrate editor and desktop compatibility paths; they are not FPS, image-quality, OpenXR, or production-readiness certificates.

## Current capability status

| Surface | Evidence state | Current result |
| --- | --- | --- |
| `FoveaSplat3D` / `FoveaSplattable` boundary | **VALIDATED** | The headless lifecycle/control contract passed 26/26 with a real one-splat PLY load; the 12,473-splat and 8,000-splat fixtures produced D3D12 captures. |
| Desktop fallback without OpenXR | **VALIDATED** | PLY rendering completed without a connected headset. |
| `.splat` parser and routing | **VALIDATED** | Godot 4.7.dev5 passed 14/14 assertions over a deterministic 256-splat round-trip and negative inputs. Rendering remains unbenchmarked. |
| `.fovea` v2 structure | **VALIDATED** | Godot 4.7.dev5 passed 28 structural and corrupt-input assertions; Rust passed five tests and reproduced the checked-in 208-byte fixture exactly. |
| Native `.fovea` rendering | **EXPERIMENTAL** | The default CPU passthrough produced a framed green/brown 800×600 D3D12 capture from 12,473 canonical records (11,808 after cleaning). Canonical palette, AABB, and linear covariance sections are exercised; image parity and instanced compute culling remain open. |
| `.spz` decoder | **PROPOSED** | The planned format is rejected until a decoder exists and is no longer advertised by the public picker. |
| GPU sorting and culling | **EXPERIMENTAL** | The depth sorter passed 30/30 D3D12 Forward+ assertions, including a complete strict back-to-front permutation for the 17,013-splat video asset; invalid results still fail closed to the exact CPU sorter. Static reuse passed 7/7 and the settled RTX 5060 Ti demo capture reports 60 FPS. Compute culling, other hardware, XR, and portability remain open. |
| OpenXR, eye tracking, and foveation | **EXPERIMENTAL** | Desktop fallbacks exist, but headset acceptance and performance gates remain open. |

Evidence-state definitions and the complete record are maintained in the [Autowiki](../../docs/autowiki/README.md#evidence-policy).

## Use inside this repository

Open the repository root in the Godot 4.7 Mono baseline. The development project already enables FoveaCore and its required autoloads.

Add a `FoveaSplat3D` node in the editor and assign `source_path`, or load the validated PLY fixture from GDScript:

```gdscript
var splat := FoveaSplat3D.new()
splat.source_path = "res://test/demo_bonsai.ply"
splat.quality_preset = FoveaSplat3D.QualityPreset.BALANCED
add_child(splat)
```

The public node exposes loading, quality, opacity, static/dynamic behavior, optional collision generation, and `.fovea` export. Call `get_advanced()` after the node is ready to reach the internal `FoveaSplattable` delegate.

`QualityPreset.AUTO` restores neutral local density and culling priority after an explicit preset, so the manager's global settings can take precedence again.

> [!WARNING]
> Copying only `addons/foveacore/` into another project is not yet a certified installation path. Project settings, autoloads, rendering support, external tools, and the native artifact contract must be validated together before redistribution.

## Editor workflow

Enabling [`plugin.cfg`](plugin.cfg) registers:

- `FoveaSplat3D`, `FoveaAsset`, and `FoveaSplattable` custom types;
- `FoveaCoreManager`, `ReconstructionManager`, and `EyeTrackingBridge` autoloads;
- the StudioTo3D dock, splat inspector, 3D gizmo, context actions, and asset picker;
- the `.fovea` resource loader and saver;
- Android export integration.

Experimental brushes, cloth, decals, multiplayer, neural, and related tools belong to the separate `fovea_labs` plugin.

## Local automation contract

[`fovea_cli_bridge.gd`](scripts/integration/fovea_cli_bridge.gd) is the optional
contract for authenticated local control tools. Version 1 exposes three bounded
operations:

- `status`: list `FoveaSplat3D` nodes and loaded splat counts;
- `validate`: fail closed on missing, escaped, unsupported, unloaded, or
  collision-incompatible sources;
- `add_splat`: add an unsaved public node from an existing project asset.

The bridge contains no network server, model-provider adapter, or scene-file
write. It limits traversal to the caller's maximum, confines sources to
`res://`, supports `.fovea`, `.ply`, and `.splat`, bounds paths and names, and
removes a newly created node if its source loads zero splats. Authentication,
mutation gates, diffs, and persistence belong to the calling control tool.

## Runtime layout

| Directory | Responsibility |
| --- | --- |
| [`scripts/`](scripts/) | Public nodes, managers, editor integration, reconstruction, VR, animation, and fallbacks |
| [`scripts/integration/`](scripts/integration/) | Optional versioned local-automation contracts |
| [`shaders/`](shaders/) | Splat drawing, compute sorting, culling, publication, and visual effects |
| [`rust/`](rust/) | Canonical native fast path and `.fovea` reader/writer implementation |
| [`gdextension/`](gdextension/) | Experimental C++ compilation target |
| [`resources/`](resources/) | XR action maps and addon resources |
| [`test/`](test/) | Godot validation, capture, GPU, format, and subsystem harnesses |

Heavy work must be deferred or threaded, bulk splat updates must avoid per-instance mutation loops, and RenderingDevice access must remain guarded in headless and compatibility modes.

## Native runtime boundary

FoveaCore can operate in a GDScript-only mode when a native binary is unavailable. Release packaging currently treats the Rust GDExtension as the canonical native artifact.

The experimental C++ target is isolated as `foveacore_cpp_init` in `foveacore_cpp.dll`; it no longer shares the Rust symbol or binary path. Its explicit Windows load harness passes locally, but release packaging remains Rust-only. See the [C++ build guide](gdextension/README_BUILD.md) for the bounded contract and remaining gates.

## Native `.fovea` format

The implemented v2 contract uses:

- `FOVEA_3D` as its 8-byte magic;
- a 72-byte little-endian header;
- 16-byte packed splat records;
- optional palette, covariance, and metadata sections.

Incompatible compression experiments require a new versioned contract. The authoritative layout is documented in [`plans/fovea_format_spec.md`](../../plans/fovea_format_spec.md).

## Validation

Run tests with the repository's Godot 4.7 baseline rather than an older system editor:

```bash
godot --headless --path . -s res://addons/foveacore/test/run_all_tests.gd -- --group=nogpu
godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_fovea_cli_bridge.gd
python addons/tools/test_validation_tools.py
```

GPU, XR, multiplayer, reconstruction, and visual claims additionally require the relevant hardware, peers or services, representative assets, and recorded acceptance gates. An exit code alone is insufficient when the log contains script, parse, load, device, or integration errors.

See the [validation matrix](../../docs/autowiki/tests/README.md) for the current commands, environment records, failures, and version gaps.
