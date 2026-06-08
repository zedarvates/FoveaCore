# Contributing to FoveaEngine 🔷

Welcome! This guide outlines the technical, architectural, and style conventions you must follow when contributing to the FoveaEngine project.

---

## 📐 Coding Style & Conventions

### GDScript Style Rules
- **Strict Typing**: All variables, constants, function arguments, and return values must be explicitly typed.
  ```gdscript
  # ❌ Incorrect
  var speed = 10.0
  func calculate_fov(pos):
      return pos.length()

  # ✅ Correct
  var speed: float = 10.0
  func calculate_fov(pos: Vector3) -> float:
      return pos.length()
  ```
- **Naming Conventions**:
  - **Classes/Types**: `PascalCase` (e.g., `FoveaCoreSplatRenderer`, `FoveaVRSubsystem`).
  - **Variables, Methods, Signals**: `snake_case` (e.g., `current_splats`, `_cull_frustum()`, `reconstruction_completed`).
  - **Constants**: `UPPER_SNAKE_CASE` (e.g., `MAX_SPLATS_PER_FRAME`).
- **Documentation**: All comments, documentation files, and docstrings must be written in **English** to ensure clarity for the open-source community.

### 🛡️ Vulkan & Multi-threading Safety
- **Vulkan Device Guards**: When querying buffers directly from the GPU (`buffer_get_data`), always guard calls to prevent hard crashes in Compatibility/OpenGL mode or headless environments.
  ```gdscript
  if culler_pipeline and culler_pipeline.rd:
      # Safe to read/write rendering buffers
  ```
- **No Blockers in `_ready()`**: Never perform heavy computations (e.g., voxelization, triangulation, parsing large files) on the main thread during `_ready()`. Delegate them using `call_deferred()`, a separate thread, or `FoveaThreadPool`.

---

## 🚀 Performance & Memory Constraints

Performance is critical for maintaining **90+ FPS in VR headsets**. Adhere to these constraints:

### 1. Batch MultiMesh Processing
- **Do NOT loop individual setters**: Never use loops calling `set_instance_transform()` or `set_instance_custom_data()` to update splats.
- **Use bulk updates**: Build and upload a `PackedFloat32Array` or `Transform3D[]` in a single call. This provides a **10x to 50x** execution speedup.

### 2. Zero-Allocation Cleaning
- Run cleaning tasks (NaN/Inf removal, outlier pruning, floater culling, decimation) directly on the raw GPU byte stream *before* decoding to maintain zero-copy efficiency.

### 3. Morton Cache Locality
- Sort splat data by their 30-bit Morton codes before binary serialization to maximize VRAM texture cache hits.

---

## 🏛️ Subsystem Decoupling Architecture

We enforce strict separation of concerns to keep the engine modular and maintainable:

- **Autoload Orchestrator (`FoveaCoreManager`)**:
  - Must remain a clean, lightweight facade/mediator.
  - Do NOT write business logic directly inside the manager.
  - Its sole purpose is to route notifications, initialize OpenXR, and orchestrate the subsystems.
- **Decoupled Domain Subsystems**:
  - Write all domain logic inside decoupled subsystems.
  - `FoveaVRSubsystem`: OpenXR initialization, HMD, and controllers tracking.
  - `FoveaFoveatedSubsystem`: Eye tracking, gaze caching, and layered LOD determination.
  - `FoveaSplatSubsystem`: Handles frustum/occlusion culling, sorting, and renderer submissions.

---

## 🦀 GDExtension & Rust Guidelines

For performance-critical code, we use Rust GDExtension:

- **Struct Layouts**: Ensure that Rust structs mapped to GPU buffers are packed and aligned to 16 bytes for compute compatibility:
  ```rust
  #[repr(C, align(16))]
  pub struct FoveaPackedSplat {
      pos_x: u16,        // 2 bytes
      pos_y: u16,        // 2 bytes
      pos_z: u16,        // 2 bytes
      norm_u: i8,        // 1 byte
      norm_v: i8,        // 1 byte
      color_index: u8,   // 1 byte
      padding1: u8,      // 1 byte
      covar_index: u16,  // 2 bytes
      opacity: u8,       // 1 byte
      layer_id: u8,      // 1 byte
      dither_seed: u8,   // 1 byte
      padding2: u8,      // 1 byte
  } // Total: 16 bytes
  ```
- **Thread Safety**: Any data passing between GDScript and Rust threads must be thread-safe. Avoid mutating shared Godot objects from parallel Rust threads.
- **Memory Safety**: Keep unsafe operations to a minimum and isolate raw pointer manipulations inside specialized Rust wrappers.
