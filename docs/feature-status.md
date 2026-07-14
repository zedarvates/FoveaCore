# Feature status

This page is the release-facing status record for the current repository. A feature is only marked **available with validation** when the code contains an integration path; it is not a claim of cross-platform production certification.

| Area | Status | Notes |
| --- | --- | --- |
| Core Godot project and addon | Available with validation | Open in Godot 4.7 and run the supplied test scene on the target renderer. |
| PLY / Gaussian-splat workflow | Available with validation | Validate each input asset and target GPU configuration. |
| FFmpeg + COLMAP StudioTo3D path | Available with validation | Requires locally installed external tools and suitable capture input. |
| WorldMirror bridge | Experimental | Requires independent local installation and hardware validation. |
| GPU culling, sorting, and advanced renderer | Experimental | Depends on RenderingDevice support and has not been certified across hardware. |
| OpenXR, eye tracking, and foveation | Experimental | Requires supported runtime and hardware smoke tests. |
| Typed animation, editing, and mobile optimizer subsystems | Experimental | API and runtime behavior require Godot validation before release. |
| DVLT bridge | Dry-run only | Inference calls are intentionally not wired. |
| AnyRecon bridge | Dry-run only | Requires missing upstream weights and inference pipeline wiring. |
| Vista4D bridge | Unavailable | Non-dry-run execution fails explicitly; no renderer or Wan inference is wired. |
| 4D capture | Unavailable | The subsystem reports an explicit unavailable error rather than fabricating output. |

## Release rule

Do not upgrade an item to production-ready based on source inspection alone. Require a reproducible Godot run, automated checks, and a target-machine smoke test. GPU, XR, and reconstruction features additionally need representative hardware and input coverage.
