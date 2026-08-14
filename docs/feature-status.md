# Feature status

This page is the release-facing status record for the current repository. A feature is only marked **available with validation** when the code contains an integration path; it is not a claim of cross-platform production certification.

| Area | Status | Notes |
| --- | --- | --- |
| Core Godot project and addon | Available with validation | Open in Godot 4.7 and run the supplied test scene on the target renderer. |
| PLY / Gaussian-splat workflow | Available with validation | Validate each input asset and target GPU configuration. |
| Binary `.splat` parser and router | Available with validation | Godot 4.7.dev5 passed a deterministic 256-splat round-trip plus corrupt, missing, and unsupported-input gates. This does not yet prove rendered-image compatibility. |
| SPZ decoding | Unavailable | The public picker rejects `.spz` until the planned decoder and fixtures exist. |
| Native `.fovea` v2 reader/writer | Available with validation | Godot 4.7.dev5 passed 28 structural, packed-record, corrupt-input, and Rust-fixture assertions. Rust passed five tests and reproduced the checked-in 208-byte fixture exactly. This is not rendering proof. |
| Native `.fovea` renderer | Experimental | Dynamic registration and a deterministic CPU passthrough produced a framed green/brown D3D12 capture from 12,473 canonical records (11,808 after cleaning). Canonical palette indices, asset bounds, and already-linear covariance scales are applied without shader errors. A synthetic two-instance GPU layout/readback passes; representative native image parity and acceleration remain uncertified. |
| Local CLI automation contract | Available with validation | Contract v1 performs bounded status, unsaved add, and validation operations without starting a listener or writing files. The real CLI/Fovea GDScript integration loads a one-splat fixture; native, GPU, and XR paths remain separate gates. |
| FFmpeg + COLMAP StudioTo3D path | Available with validation | Requires locally installed external tools and suitable capture input. |
| WorldMirror bridge | Experimental | Requires independent local installation and hardware validation. |
| GPU culling and sorting | Experimental | D3D12 instanced readback preserves two canonical records and instance IDs, but representative asset/depth coverage is still open. The depth sorter rejects an incomplete padded permutation and falls back to exact CPU ordering, so GPU sorting is not certified. |
| Voxel HLOD | Experimental | CPU macro-splat generation and distance selection are integrated; this is not yet a full Mip-Splatting anti-aliasing implementation. |
| Tile-based rasterization | Experimental | The 16×16 compute path passes 10/10 D3D12 dispatch/readback checks on an RTX 5060 Ti, including a transparent-to-opaque 64×64 target. Standard-renderer equivalence and measured performance remain open. |
| OpenXR, eye tracking, and foveation | Experimental | Requires supported runtime and hardware smoke tests. |
| Multiplayer VR synchronization | Experimental | A loopback two-process ENet test validates pose convergence, authority-mediated brush replication, and disconnect cleanup. This does not prove a two-headset OpenXR session. |
| ComfyUI image-to-splat bridge | Experimental | Configurable API workflows use upload, prompt, history, and view endpoints; supported splat artifacts are validated before being written and assigned to `FoveaSplat3D`. A loopback server proves the HTTP contract, not a real third-party 3DGS/Blender installation. |
| Typed animation, editing, and mobile optimizer subsystems | Experimental | API and runtime behavior require Godot validation before release. |
| DVLT bridge | Dry-run only | Inference calls are intentionally not wired. |
| AnyRecon bridge | Dry-run only | Requires missing upstream weights and inference pipeline wiring. |
| Vista4D bridge | Unavailable | Non-dry-run execution fails explicitly; no renderer or Wan inference is wired. |
| 4D capture | Unavailable | The subsystem reports an explicit unavailable error rather than fabricating output. |

## Release rule

Do not upgrade an item to production-ready based on source inspection alone. Require a reproducible Godot run, automated checks, and a target-machine smoke test. GPU, XR, network, AI-generation, and reconstruction features additionally need representative hardware, peers/services, and input coverage.
