# CLAUDE.md - FoveaEngine Development Guide

## Build & Test Commands
- **GDExtension**: `scons target=template_debug platform=windows` (if source available)
- **Godot Project**: Open in Godot 4.6.2 Stable
- **Test Scene**: `godot --scene res://test/fovea_test_scene.tscn`
- **Reconstruction Tools**:
  - `python addons/foveacore/scripts/reconstruction/star_bridge.py`: Monocular bridge.
  - `python addons/foveacore/scripts/reconstruction/star_simulator.py`: Logic simulator.

## External Dependencies
- **FFmpeg**: Required for frame extraction. Path set in Project Settings.
- **COLMAP**: Required for SfM path (Standard).
- **InSpatio-World**: Required for Fast Path (DA3/STAR).
- **Depth-Anything-3**: Model weights for precise monocular depth.

## Code Style & Architecture
- **GDScript**: Use 4.x/4.6+ features (typed arrays, lambdas). Avoid chaining void methods.
- **C++/GDExtension**: Core performance logic (Splat sorting, Foveation).
- **StudioTo3D**: Modular pipeline (Extraction -> Geometry -> Training).
- **STAR Architecture**: Causal temporal cache + DA3 Depth Maps for 4D consistency.

## 👁️ FoveaCore Codage Rules & Constraints

### 📐 General Guidelines
- **Strictly Typed GDScript**: Always specify types for variables, function arguments, and return values (e.g. `var x: float = 1.0`, `func my_func(a: String) -> void`).
- **No Blocking Calls in `_ready()`**: Heavy operations like voxelization or collision shape generation MUST be executed via `call_deferred()` or in a background thread to prevent viewport freezes.
- **Null Safety on Vulkan Devices**: Always safely guard `culler_pipeline` and `culler_pipeline.rd` before querying GPU buffers (`buffer_get_data`) to prevent hard crashes in Compatibility or headless modes.
- **Strict Naming Convention**: Use PascalCase for class names and snake_case for local variables/methods. Comments and documentation should favor English for open-source clarity.

### 🚀 Performance & Memory
- **Batch Processing Rule**: Never loop `set_instance_transform()` or `set_instance_custom_data()` for loading or updating splats in MultiMesh. Use direct bulk writes via `transform_array` and `custom_data_array` (PackedFloat32Array) for a **10x to 50x** execution speedup.
- **Zero Allocations for Cleaning**: Run `FoveaSplatCleaner` operations (outliers pruning, floater culling with `SpatialHashGrid`, and decimation) directly on the raw GPU byte stream *before* decoding to maintain zero-copy efficiency.
- **Morton Cache Locality**: Arrange splat data sorted by 30-bit Morton codes before binary serialization to maximize VRAM texture cache hits.

### 🛡️ Survival Rules & Subsystem Architecture
- **Subsystem Decoupling**: Keep `FoveaCoreManager` as a clean, lightweight autoload orchestrator. All domain logic must reside in its decoupled subsystems:
  - `FoveaVRSubsystem` — Handles OpenXR initialization and VR rigs.
  - `FoveaFoveatedSubsystem` — Handles eye tracking and gaze caching.
  - `FoveaSplatSubsystem` — Handles sorting, frustum/occlusion culling, and renderer submissions.
- **Voxelizer Verification**: `FoveaVoxelizer` must strictly guard input files, verifying the `.fovea` extension and validating the 8-byte `FOVEA_3D` magic header before parsing to avoid corrupted collision geometries.
- **Clay Deformer Non-Destructiveness**: Modifications to splat positions via `FoveaClayDeformer` must always operate on a cached snapshot of original transforms to ensure edits are completely reversible.

## Git Workflow
- Keep commits focused on specific features/fixes.
- Use `rtk` for optimized token usage during commit/push operations.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (90-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk vitest run          # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%)
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->