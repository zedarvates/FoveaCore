# FoveaEngine Multiplayer Sync Specification

This document details the multiplayer synchronization protocol and state replication architecture implemented for FoveaEngine VR MMO spaces.

---

## 1. Network Architecture

The synchronization is managed by `FoveaMultiplayerSync` node using Godot's native high-level Multiplayer API. It operates symmetrically on all clients and servers to replicate VR rig poses and interactive splat changes.

```
       [Local Client (VR Rig)]
                 │
                 ├── (Unreliable) update_peer_pose() ──► [Remote Peers]
                 │                                            │
                 │                                      NetworkInterpolator
                 │                                            │
                 │                                      Interpolated Pose
                 │
                 └── (Reliable) replicate_brush_stroke() ─► [Remote Peers]
                                                              │
                                                        SplatBrushEngine
                                                              │
                                                        Splat Mod (VRAM)
```

---

## 2. Poses Synchronization (VR Rig)

VR rigs require low-latency, high-frequency updates. To optimize bandwidth and CPU execution, pose updates are sent unreliably over the network.

### RPC Definition

```gdscript
@rpc("any_peer", "unreliable_ordered")
func update_peer_pose(
    head_pos: Vector3, head_rot: Quaternion, head_vel: Vector3,
    left_pos: Vector3, left_rot: Quaternion, left_vel: Vector3,
    right_pos: Vector3, right_rot: Quaternion, right_vel: Vector3,
    timestamp: float
) -> void
```

### estimated Velocities
Velocities are calculated locally before transmission by taking the backward difference between the current frame's position and the previous frame's position divided by delta time:
$$v = \frac{p_{t} - p_{t-1}}{\Delta t}$$

---

## 3. Network Interpolation

To mask latency and packet jitter, remote player rigs are not positioned directly. Instead, positions are fed into `NetworkInterpolator` instances (one for the head, left hand, and right hand respectively).

- **Hermite Interpolation (default)**: Uses the position and velocity tangencies of the two bounding snapshots surrounding the target time to construct a smooth cubic Bezier curve.
- **Dead Reckoning fallback**: If packets are delayed or dropped, the interpolator predicts player positions using the last known velocity and elapsed time:
  $$p_{predicted} = p_{last} + v_{last} \times \Delta t_{elapsed}$$

---

## 4. SplatBrush Stroke Replication

Unlike poses, splat edits must be replicated reliably to prevent desynchronization of the environment's state.

### Replicating Stroke vs Splat Deltas
Transmitting thousands of modified individual splat coordinates over the network is highly bandwidth-intensive. Instead, FoveaEngine replicates the **brush parameters and global hit position**. Since the paint application is deterministic, all clients calculate and modify the exact same splat indices locally.

### RPC Definition

```gdscript
@rpc("any_peer", "call_local", "reliable")
func replicate_brush_stroke(
    splattable_path: NodePath,
    global_position: Vector3,
    mode: int,
    radius: float,
    color: Color,
    opacity: float,
    flow_dir: Vector3
) -> void
```

1. **Detection**: `SplatBrushEngine` emits the `brush_applied` signal when a stroke alters any local splat.
2. **Transmission**: `FoveaMultiplayerSync` catches the signal and broadcasts `replicate_brush_stroke` to all peers.
3. **Application**: Remote peers resolve the target `FoveaSplattable` by path, instantiate a silent `SplatBrushEngine` (setting `is_replicating = true` to prevent recursive signals), apply the paint stroke, and trigger a redraw of the splat instance arrays.
