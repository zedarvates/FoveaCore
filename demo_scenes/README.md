<div align="center">
  <img src="../icon.svg" alt="FoveaEngine logo" width="88" />

  <h1>Experimental demo-scene roadmap</h1>
  <p>Planned showcases for FoveaEngine animation, deformation, and reconstruction subsystems.</p>
  <p><a href="../README.md">Project overview</a> · <a href="../demo/README.md">Working PLY demo</a> · <a href="../docs/feature-status.md">Feature status</a></p>
</div>

> [!WARNING]
> The eight scenes in this directory are placeholders, not runnable feature demos. Each currently contains only an empty `Node3D` root. They remain in the repository as named integration targets and must not be used as evidence that the planned behavior works.

## Working demo

![Bonsai Gaussian-splat fixture rendered by FoveaEngine in Godot](../docs/images/foveaengine-bonsai-runtime.png)

<p align="center"><sub>For a runnable scene today, use <a href="../demo/drop_a_ply.tscn"><code>demo/drop_a_ply.tscn</code></a>. This capture proves the PLY runtime path; it does not validate the placeholder scenes below.</sub></p>

## Placeholder catalog

| Scene | Intended showcase | Planned subsystem | Current state |
| --- | --- | --- | --- |
| [`demo_forest.tscn`](demo_forest.tscn) | Wind-driven foliage | [`FoveaFlowFieldAnimator`](../addons/foveacore/scripts/advanced/fovea_flow_field_animator.gd) | Empty `Node3D` placeholder |
| [`demo_curtain.tscn`](demo_curtain.tscn) | Cloth moving in a flow field | [`FoveaSplatCloth3D`](../addons/foveacore/scripts/advanced/fovea_splat_cloth.gd) | Empty `Node3D` placeholder |
| [`demo_blob.tscn`](demo_blob.tscn) | Organic covariance morphing | [`FoveaMorphCovarianceAnimator`](../addons/foveacore/scripts/advanced/fovea_morph_covariance_animator.gd) | Empty `Node3D` placeholder |
| [`demo_water.tscn`](demo_water.tscn) | Animated water-like splats | [`FoveaMorphCovarianceAnimator`](../addons/foveacore/scripts/advanced/fovea_morph_covariance_animator.gd) | Empty `Node3D` placeholder |
| [`demo_flame.tscn`](demo_flame.tscn) | Volumetric flipbook animation | [`FoveaFlipbookAnimator`](../addons/foveacore/scripts/advanced/fovea_flipbook_animator.gd) | Empty `Node3D` placeholder |
| [`demo_magic.tscn`](demo_magic.tscn) | Stylized magic effect | [`FoveaFlipbookAnimator`](../addons/foveacore/scripts/advanced/fovea_flipbook_animator.gd) | Empty `Node3D` placeholder |
| [`demo_creature.tscn`](demo_creature.tscn) | Rigged splat character | [`FoveaCharacterWizard`](../addons/foveacore/scripts/advanced/fovea_character_wizard.gd) | Empty `Node3D` placeholder |
| [`demo_scanned.tscn`](demo_scanned.tscn) | Animated reconstructed scene | [`FoveaNeuralOffsetAnimator`](../addons/foveacore/scripts/advanced/fovea_neural_offset_animator.gd) | Empty `Node3D` placeholder |

The previously documented `demo_desktop.tscn` selector is not present in this directory.

## Promotion criteria

A placeholder should be described as a working demo only after it has:

1. a committed scene with a camera, environment, representative asset, and configured subsystem;
2. a clean Godot load with no script, resource, or shader errors;
3. a reproducible interaction or animation check;
4. a current screenshot or short capture identifying the tested renderer and hardware;
5. an explicit maturity note aligned with the [feature status matrix](../docs/feature-status.md).

Headless loading alone is not proof of visual correctness, animation quality, VR behavior, or performance.
