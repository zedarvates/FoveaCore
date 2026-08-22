# Ultimate Odycer Splat Delta Protocol v1

`FoveaSplatDeltaProtocol` defines a CPU-only, transport-neutral contract for
authoritative sparse changes to immutable `.fovea` assets. It is intended to be
implemented byte-for-byte by Zig2 before the packet is connected to an RPC.

## Identity and authority

An asset keeps the content-addressed ID published by `FoveaAssetRegistry`:

```text
sha256:<64 lowercase hexadecimal characters>
```

A splat is addressed by the collision-free tuple `(asset_id, splat_index)` and
has the diagnostic string form:

```text
sha256:<digest>/<decimal splat index>
```

The digest is stored once per batch; each record carries only a `u32` index.
Clients must treat received batches as server-authoritative. A receiver applies
a batch only when its local revision equals `base_revision`, then advances to
`revision`. Snapshot requests and rollback remain transport-layer work.

## Compressed envelope

All integers are little-endian.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII magic `FVZ1` |
| 4 | 4 | Uncompressed size, `u32` |
| 8 | remaining | ZSTD-compressed raw batch |

The declared raw size is bounded to 114,752 bytes. A decoder rejects oversized
declarations before decompression.

## Raw batch header

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII magic `FVND` |
| 4 | 2 | Protocol version `1`, `u16` |
| 6 | 2 | Flags `0`, `u16` |
| 8 | 8 | Base revision, `u64` |
| 16 | 8 | New revision, `u64` |
| 24 | 4 | Immutable asset splat count, `u32` |
| 28 | 4 | Sparse change count, `u32` |
| 32 | 32 | Binary SHA-256 digest |

The batch contains between 1 and 4,096 unique changes. `revision` must be
strictly greater than `base_revision`.

## Fixed 28-byte change record

| Relative offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | Splat index, `u32` |
| 4 | 4 | Field mask, `u32` |
| 8 | 4 | Position X/Y, two FP16 values |
| 12 | 2 | Position Z, FP16 |
| 14 | 2 | Reserved zero padding |
| 16 | 4 | Color R/G deltas, two FP16 values |
| 20 | 4 | Color B/A deltas, two FP16 values |
| 24 | 4 | Normal U/V deltas, two FP16 values |

Field mask bits are `1` for position, `2` for color, and `4` for normal.
Unselected storage slots remain zero and are not exposed by the decoder.

## Fail-closed rules

- The asset ID must contain one valid lowercase SHA-256 digest.
- Splat indices must be unique and lower than the declared splat count.
- Position, color, and normal deltas must contain finite values.
- A record must select at least one supported field and no unknown mask bits.
- Raw size, record count, protocol version, flags, and both magic values must
  match exactly.
- Corrupt or incomplete ZSTD data is rejected before any change is returned.

## Integration boundary

### Godot client ownership

`FoveaClientSplatState` is the canonical CPU-side owner of received sparse
deltas inside the player client. It is configured from the locally loaded
asset ID, splat count, and optional snapshot revision. `apply_packet()` then:

1. decodes the packet locally;
2. checks that asset identity and layout match the loaded `.fovea` asset;
3. requires `base_revision` to equal the current client revision;
4. applies all changes to temporary dictionaries;
5. publishes those dictionaries and the new revision atomically.

The class has no RPC, server, socket, or GPU dependency. Godot remains
responsible for loading, retaining, rendering, animating, and editing splats.
A future renderer adapter may consume its sparse dictionaries without changing
the wire format or transferring rendering ownership elsewhere.

`FoveaClientSplatRendererBridge` now performs that CPU boundary conversion. It
exports a defensive sparse snapshot, then prepares the existing
`FoveaDeltaManager` layout: one dense 24-byte FP16 record per splat, including
position, color, normal, and padding. Mutating the returned payload cannot
mutate the client state.

The bridge does not allocate a GPU buffer. Dense payload creation costs
`24 * splat_count` bytes and must therefore remain behind a renderer-side VRAM
budget before it is used for massive assets. Dynamic residency, eviction, and
sparse GPU updates remain a separate scalability gate; this CPU test is not
evidence for two-million-splat VR performance.

### Client VRAM admission and residency

`FoveaClientVramBudget` provides the required admission gate before dense
payload construction. Its capacity is expressed in bytes and can be changed at
runtime. Each content-addressed asset reservation records byte size, priority
from 0 to 100, and a monotone last-use counter.

`build_budgeted_renderer_payload()` reserves `24 * splat_count` bytes before
calling the dense CPU packer. Admission follows these rules:

- a single payload larger than total capacity is rejected before allocation;
- an incoming asset may evict only residents of lower or equal priority;
- eviction orders candidates by lowest priority, then least-recent use;
- a rejected request leaves the complete residency map unchanged;
- shrinking capacity evicts lowest-priority/LRU residents until usage fits;
- explicit release immediately returns the reservation to the local budget.

This is a deterministic CPU residency model, not a query of physical GPU
memory. Connecting reservations to actual `RenderingDevice` buffer creation,
RID release, and measured headset memory pressure remains a separate GPU gate.

### Real Godot RID ownership

`FoveaClientGpuResidency` connects admitted payloads to a caller-provided
Godot `RenderingDevice`. It is the sole owner of the storage-buffer RIDs it
creates. A successful replacement or admission frees RIDs evicted by the CPU
budget; explicit release and cleanup free the remaining RIDs and return their
reservations.

On 2026-08-22, the focused GPU lifecycle test passed 17/17 assertions using
Godot 4.7-dev5, D3D12 Forward+, and an NVIDIA GeForce RTX 5060 Ti. The test
created real 240-byte storage buffers, read one back, verified its FP16 client
delta, exercised LRU eviction, and confirmed cleanup returned budget usage to
zero. This proves the focused RID lifecycle on that machine, not headset memory
pressure or massive-scene performance.

The broader shader-compilation probe remains a separate open gate: the same
run reported no SPIR-V for `gpu_culling_legacy.glsl` and a stage-4 diagnostic
for `splat_animate_advanced.glsl`. Those unrelated shader failures were not
modified or hidden by the residency work.

### External synchronization remains optional

This implementation proves serialization, validation, and local round-trip
behavior only. It does not prove:

- Zig2 byte compatibility;
- RPC ordering, retransmission, interest management, or bandwidth budgets;
- revision-gap recovery, snapshots, rollback, or reconciliation;
- deterministic server-side sculpt/flow simulation;
- multi-client, packet-loss, OpenXR, GPU, or MMO-scale behavior.
