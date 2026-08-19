# Public release checklist

This checklist separates implemented prototypes from evidence required before changing the repository visibility. A checked implementation is not a production certification.

## P0 — repository hygiene

- [x] Replace tracked machine-specific `.mcp.json`, `.claude/settings.json`, and `.botte/config.json` with portable examples while retaining ignored local copies.
- [x] Ignore local backup files such as `FoveaEngine.csproj.old*`.
- [x] Remove generated `.kilocode`, Understand Anything, Botte report, and agent payload files from the public index while retaining ignored local copies.
- [x] Initialize `botte-secrete`, verify its clean `9d184b5` checkout, and confirm that commit is reachable from the public submodule URL.
- [ ] Rotate the OpenAI credential reported by Gitleaks in historical `.kilocode/task_history.json` at commit `c2e6095`.
- [x] Rehearse the `.kilocode` purge in a disposable mirror; the rewritten 136-commit history passes Gitleaks with no leaks.
- [x] Purge `.kilocode` from the sanitized history and rerun Gitleaks; the clean public candidate scans 148 commits with no leaks and has zero reachable `.kilocode` objects.
- [ ] Replace every public remote branch and tag with the sanitized refs, then verify a fresh remote clone; the current remotes still expose the old history.
- [ ] Reconcile the current dirty worktree into a focused release branch without staging unrelated local changes.

## Feature evidence gates

### Local CLI automation

- [x] Publish a provider-neutral contract for status, unsaved add, and validation operations.
- [x] Keep listener, authentication, mutation approval, scene saving, and model-provider calls outside FoveaCore.
- [x] Reject escaped/missing/unsupported sources, invalid settings, incompatible collision requests, over-budget scans, and zero-splat loads.
- [x] Validate the real bridge under Godot 4.7-dev5 and replay the real CLI against a temporary GDScript-only Fovea project.
- [ ] Validate the same control path with the packaged native artifact and a representative splat before treating native acceleration as covered.

### ComfyUI bridge

- [x] Godot uploads an input image and submits a deterministic API-format Img2Img graph.
- [x] Prompt, checkpoint, denoise, endpoint, and output-node discovery are configurable and unit-tested.
- [x] Generic API workflows discover and validate `.fovea`, `.ply`, and `.splat` outputs before importing them into `FoveaSplat3D`.
- [x] A loopback server validates `upload → prompt → history → view`, file persistence, and one-splat loading under Godot 4.7-dev5.
- [ ] Add a reviewed reference ComfyUI → 3DGS/Blender API workflow and run it end to end with a representative generated artifact.
- [ ] Run the workflow against a clean local ComfyUI installation and record model/custom-node requirements.

### HLOD and Mip-Splatting

- [x] Voxel macro-splat generation and distance-based selection are integrated.
- [x] Empty input, grouping, weighted color, and non-destructive source handling are unit-tested.
- [ ] Implement and validate the 3D/2D anti-alias filtering required for a full Mip-Splatting claim.
- [ ] Capture visual transition and frame-time evidence on small, medium, and million-splat scenes.

### Tile-based rasterization

- [x] The 16×16 shader, local sort/blend path, renderer flag, and dispatch harness exist.
- [x] Run the dispatch on a real RenderingDevice: Godot 4.7-dev5/D3D12 on an RTX 5060 Ti passes 10/10 checks, including a transparent-to-opaque 64×64 texture readback.
- [ ] Compare output against the standard renderer and publish measured GPU timings without claiming synthetic speedups.

### Multiplayer VR synchronization

- [x] Single-process pose interpolation and replicated brush logic pass under Godot 4.7-dev5.
- [x] A two-process loopback ENet test covers join, pose convergence, authority brush convergence, and disconnect cleanup.
- [x] Edit RPCs enforce server authority, payload and editable-root validation, and per-peer rate limits.
- [ ] Validate two OpenXR peers under representative latency and packet loss.

## README and release proof

- [x] The README has a real editor screenshot and a real runtime screenshot with scoped captions.
- [x] `README.md`, `README_CN.md`, `ROADMAP.md`, and `docs/feature-status.md` distinguish experimental paths from validated ones.
- [x] Track both README screenshots and validate 86 Markdown files, 175 working-tree local links, the MIT license, dependency guide, and required workflows/assets.
- [x] Run the same local documentation gate from a clean index export; 86 Markdown files, 122 index-snapshot local links, and all 9 required files pass.
- [ ] Rerun `python tools/check_public_docs.py --external` immediately after changing visibility; only the private FoveaCore workflow URL and badge currently return 404.
- [x] Validate the prepared index in isolation: all 197 GDScript classes load and the corrected `nogpu` group passes 57/57 suites while explicitly skipping 6 GPU/integration suites.
- [x] Validate the prepared index C# and Rust surfaces: C# Release builds with 0 errors; Rust passes 5 tests, strict Clippy, and an optimized 32-crate build.
- [x] Add a real C# test project; `tests/FoveaEngine.Tests` now covers the Godot-free Morton encoder with 3 passing xUnit tests, while `FoveaEngine.csproj` still excludes that project from the Godot assembly.
- [x] Validate representative prepared-index GPU and visual paths: tile dispatch 10/10, instanced layout/readback 32/32 with no skips, and a recognizable auto-framed 12,473-splat PLY capture with exact-count CPU fallback when GPU sorting is incomplete.
- [x] Validate all repository Python syntax, the four offset-field baker tests, a Godot-loaded generated resource, the portable validation tools, and the public-docs gate.
- [ ] Run representative GPU/visual checks, Python validation, and the Botte checkup on the final clean branch.
- [ ] Verify GitHub Actions on the rewritten, clean remote before announcing the public release.
