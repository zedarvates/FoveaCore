# Feature status

This page is the release-facing status record for the current repository. A feature is only marked **available with validation** when the code contains an integration path; it is not a claim of cross-platform production certification.

| Area | Status | Notes |
| --- | --- | --- |
| Core Godot project and addon | Available with validation | Godot 4.7.dev5 passed the 30-assertion manager facade contract and the 4-assertion dynamic `.fovea` lifecycle contract in headless desktop fallback. Target-renderer, GPU, and XR acceptance remain separate. |
| PLY / Gaussian-splat workflow | Available with validation | The public-node/delegate contract passed 26/26 with a real one-splat PLY load. The local Furby reference additionally proves a real-camera-video path through 60 views, 18,774 trained Gaussians, and a sanitized 17,013-splat D3D12 runtime asset; its source media remains non-redistributable. See the [demo evidence record](../demo/README.md). Each new asset and target GPU still requires validation. |
| Binary `.splat` parser and router | Available with validation | Godot 4.7.dev5 passed a deterministic 256-splat round-trip plus corrupt, missing, and unsupported-input gates. This does not yet prove rendered-image compatibility. |
| SPZ decoding | Unavailable | The public picker rejects `.spz` until the planned decoder and fixtures exist. |
| Native `.fovea` v2 reader/writer | Available with validation | Godot 4.7.dev5 passed 28 structural, packed-record, corrupt-input, and Rust-fixture assertions. Rust passed five tests and reproduced the checked-in 208-byte fixture exactly. This is not rendering proof. |
| Native `.fovea` renderer | Experimental | Dynamic registration and a deterministic CPU passthrough produced a framed green/brown D3D12 capture from 12,473 canonical records (11,808 after cleaning). Canonical palette indices, asset bounds, and already-linear covariance scales are applied without shader errors. A synthetic two-instance GPU layout/readback passes; representative native image parity and acceleration remain uncertified. |
| Experimental C++ GDExtension | Experimental | Artifact ownership is separated from the packaged Rust runtime. The Windows release build produced `foveacore_cpp.dll`, export inspection found `foveacore_cpp_init`, Godot instantiated `FoveaRenderer`, and the missing-binary control exited non-zero. Local Windows CI smoke now exists; remote certification, other targets, image parity, and packaging remain open. |
| Local CLI automation contract | Available with validation | Contract v1 performs bounded status, unsaved add, and validation operations without starting a listener or writing files. The real CLI/Fovea GDScript integration loads a one-splat fixture; native, GPU, and XR paths remain separate gates. |
| FFmpeg + COLMAP StudioTo3D path | Available with validation | The Furby reference records a real camera capture reaching gsplat and `FoveaSplat3D`; reproduction requires locally installed external tools, suitable static-subject footage, and explicit media rights. |
| WorldMirror bridge | Experimental | Requires independent local installation and hardware validation. |
| GPU culling and sorting | Experimental | D3D12 Forward+ depth sorting passed 30/30 assertions over six sizes through the exact 17,013-splat video asset, with a complete strict back-to-front permutation; invalid results still fail closed to CPU. Static-frame reuse passed 7/7 and the settled RTX 5060 Ti capture reports 60 FPS. Instanced compute culling, other hardware, XR, and portability remain uncertified. |
| `.fovea4d` motion sidecar | Experimental | GDScript and Rust validate the v1 format and cross-language fixtures. An 8,000-splat, 8x8x8, 16-unique-key synthetic gate produced 213,288 combined bytes, 0.011233% normalized position RMSE, exact loop closure, a 492 ms one-time CPU cache build, and 0.322 ms median cached sampling. A focused RTX 5060 Ti/D3D12 readback matched CPU positions within one animated-AABB quantization unit and preserved non-position fields. Real sequences, visual parity, million-splat scale, mobile, and XR remain open. |
| Voxel HLOD | Experimental | CPU macro-splat generation and distance selection are integrated; this is not yet a full Mip-Splatting anti-aliasing implementation. |
| Tile-based rasterization | Experimental | The 16×16 compute path passes 10/10 D3D12 dispatch/readback checks on an RTX 5060 Ti, including a transparent-to-opaque 64×64 target. Standard-renderer equivalence and measured performance remain open. |
| Transparency framebuffer harness | Experimental | Godot 4.7.dev5/D3D12 measured one and two overlapping 50% red layers at 0.498 and 0.749 versus 0.500 and 0.750 expectations; the positive gate exited cleanly and the forced negative control exited non-zero. Production splat-shader and layout parity remain open. |
| OpenXR, eye tracking, and foveation | Experimental | Requires supported runtime and hardware smoke tests. |
| Multiplayer VR synchronization | Experimental | A loopback two-process ENet test validates pose convergence, authority-mediated brush replication, and disconnect cleanup. This does not prove a two-headset OpenXR session. |
| Spatial chunk streaming | Experimental | Morton chunks are prioritized by camera distance and gaze, admitted under a deterministic splat-count budget per update, loaded asynchronously into bounded CPU RAM, and evicted by LRU. This is not direct SSD-to-VRAM transfer or a 90 FPS headset proof. |
| ComfyUI image-to-splat bridge | Experimental | Configurable API workflows use upload, prompt, history, and view endpoints; supported splat artifacts are validated before being written and assigned to `FoveaSplat3D`. A loopback server proves the HTTP contract, not a real third-party 3DGS/Blender installation. |
| Typed animation, editing, and mobile optimizer subsystems | Experimental | Several focused API tests exist, but the broader prototype set is not uniformly wired or composable. Each path still needs explicit runtime and target validation before release. |
| DVLT bridge | Dry-run only | Inference calls are intentionally not wired. |
| AnyRecon bridge | Dry-run only | Requires missing upstream weights and inference pipeline wiring. |
| Vista4D bridge | Unavailable | Non-dry-run execution fails explicitly; no renderer or Wan inference is wired. |
| 4D capture | Unavailable | The subsystem reports an explicit unavailable error rather than fabricating output. |

## Release rule

Do not upgrade an item to production-ready based on source inspection alone. Require a reproducible Godot run, automated checks, and a target-machine smoke test. GPU, XR, network, AI-generation, and reconstruction features additionally need representative hardware, peers/services, and input coverage.
