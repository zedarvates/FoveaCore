# Hermes Blender Bridge Design Spec

The Hermes Blender Bridge establishes a bidirectional, real-time WebSocket connection between Blender and FoveaEngine (Godot). It allows autonomous AI agents and users to synchronize views, export camera parameters, and stream transformations between the two environments.

## Architecture Overview

```
┌─────────────────┐                     ┌─────────────────┐
│     Blender     │  ◄── WebSocket ──►  │   FoveaEngine   │
│  (Python Addon) │      (TCP:8012)     │    (GDScript)   │
└─────────────────┘                     └─────────────────┘
```

The bridge uses a lightweight JSON-based message protocol. Blender acts as either a server or client depending on setup, but by default FoveaEngine hosts the server on port `8012`.

## WebSocket Message Protocol

Every message sent across the bridge must be a valid JSON object containing a `type` field, a `sender` field ("blender" or "godot"), and a `payload` dictionary.

```json
{
  "type": "command_type",
  "sender": "blender",
  "payload": {}
}
```

### 1. Viewport Synchronization (Real-time View/Camera Sync)
Provides camera alignment between the Blender 3D Viewport and Godot's Camera3D.

- **Type**: `sync_camera`
- **Payload**:
  - `transform`: Flat 16-float array representing the 4x4 transform matrix (column-major).
  - `fov`: Vertical field of view in degrees.
  - `near`: Near clipping plane.
  - `far`: Far clipping plane.

### 2. Object Manipulation & Hierarchy Sync
Allows selecting, moving, rotating, and scaling instanced splat assets or dummy meshes.

- **Type**: `sync_objects`
- **Payload**:
  - `objects`: Array of objects:
    ```json
    [
      {
        "name": "Splat_Bonsai_01",
        "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 1.5,0.5,-2.0,1]
      }
    ]
    ```

### 3. Reconstruction Commands
Instructs Blender to bake geometry, export camera extrinsics/intrinsics, or trigger reconstruction pipelines.

- **Type**: `trigger_bake`
- **Payload**:
  - `object_name`: Target object to bake.
  - `resolution`: Voxel size or density multiplier.

- **Type**: `export_cameras`
- **Payload**:
  - `target_dir`: Path where `camera_params.json` or COLMAP workspace should be written.

## Bidirectional Synchronization Flow

1. **Connection Hook**: On startup, FoveaEngine starts listening on port `8012`. Blender connects automatically.
2. **Viewport Focus**: When the user navigates inside Blender, a viewport handler catches the camera matrix change and dispatches a `sync_camera` message. FoveaEngine updates its viewport camera immediately.
3. **Asset Placement**: Placing or modifying objects in Blender triggers an update of instance positions inside FoveaEngine's `FoveaInstancedSplatRenderer` using delta transforms.
