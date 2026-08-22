# FoveaCore Knowledge Base

## Current surface

| Capability | Evidence state | Authoritative path |
| --- | --- | --- |
| Public splat node | VALIDATED (PLY fixtures) | `addons/foveacore/scripts/fovea_splat_3d.gd` |
| `.splat` parser and router | VALIDATED (14/14 assertions on Godot 4.7.dev5) | `addons/foveacore/scripts/reconstruction/splat_format_loader.gd` |
| `.spz` decoder | PROPOSED; excluded from the public picker | Planned loader work only |
| Public node / advanced delegate boundary | VALIDATED (headless lifecycle and controls) | `FoveaSplat3D` → `FoveaSplattable` propagation passed 26/26, including runtime-only ownership and preset reset behavior. |
| Manager and decoupled subsystems | VALIDATED (headless facade/lifecycle) | The facade contract passed 30/30 and dynamic `.fovea` registration passed 4/4 on Godot 4.7.dev5; GPU and XR execution remain separate experimental gates. |
| GPU-aware sorting with CPU fallback | EXPERIMENTAL; invalid GPU permutations fall back to CPU | `addons/foveacore/scripts/fovea_splat_subsystem.gd` and sorter implementations |
| Native Rust fast path | VALIDATED (format contract and local Windows release build) | The locked workspace passed 5/5 tests and Clippy with warnings denied; its generator reproduced the tracked 208-byte v2 fixture exactly. Runtime performance and portability remain experimental. |
| C++ GDExtension surface | EXPERIMENTAL; distinct Windows artifact loads locally, while CI and cross-platform parity remain open | `addons/foveacore/gdextension/` |
| `.fovea` v2 structural reader/writer | VALIDATED on Godot 4.7.dev5 (28/28) and Rust (5 tests) | `addons/foveacore/scripts/fovea_binary_format.gd`, GDScript loader/saver, and Rust fast path |
| Native `.fovea` runtime rendering | EXPERIMENTAL; D3D12 capture is framed and green/brown through the CPU passthrough, while image parity and compute culling remain open | `addons/foveacore/scripts/fovea_splattable.gd` and native renderers |
| GPU, XR, and foveated performance | EXPERIMENTAL | Requires target-hardware measurements |

## Loader contract

- Accept only supported extensions at the public node.
- Validate `.fovea` magic, version, header length, counts, offsets, and section sizes before reading buffers.
- Preserve a CPU-safe fallback where the native path is absent.
- Treat empty or malformed input as a typed failure, not an empty successful asset.
- Keep reader/writer compatibility covered by golden fixtures across GDScript and Rust.

## Renderer contract

- Transform splats into world space before animation, sorting, and submission.
- Use GPU sorting only when a valid device exists and the supported splat limit is not exceeded.
- Retain a deterministic CPU depth-sort fallback.
- Avoid per-instance MultiMesh mutation loops for bulk splat updates.
- Guard all GPU buffer reads in headless and compatibility modes.
- Record frame-time, splat count, VRAM, renderer, resolution, and hardware with performance claims.

## Compression contract

The implemented v2 record is 16 bytes/splat and uses a color palette plus covariance codebook. The GDScript and Rust readers validate header, count, payload, and optional-section layout before parsing. The proposed 8-byte format is not compatible with the current v2 readers and must receive a distinct versioned contract before implementation.

Required future comparison metrics are file size, encode time, decode time, peak RAM, peak VRAM, PSNR, SSIM, and headset frame time.

## Shader contract

- Shader interfaces and buffer layouts must be versioned with the producer layout.
- Compute paths must validate dispatch bounds.
- tile_rasterizer.glsl PackedSplat is four uint words (16 bytes). GPU dummy buffers and GPUCullerPipeline.SPLAT_BYTE_SIZE must keep that stride.
- Foveated and motion-adaptive effects must degrade safely without eye tracking.
- Visual changes require golden renders or an explicit hardware-blocked result.

## Packed-record GPU audit

The standard and artistic render paths interpret the high byte of `data3` as
`brush_type`, using the canonical mapping `0=Stone`, `1=Sponge`, `2=Gaussian`,
`3=Drybrush`, `4=Stipple`. GPU culling, skinning, and delta-animation paths
preserve that byte when they only update position or opacity.

The instanced output record is 24 bytes: the canonical 16-byte `.fovea` record
is untouched, followed by `local_idx: u32` and `instance_id: u32`. GPU
publication reads the 24-byte stride but writes only the four canonical words
to its texture.

`FoveaInstancedSplatLayout` is the single GDScript authority for these sizes
and offsets; the culler, renderer, CPU decoder, and tests consume it directly.
