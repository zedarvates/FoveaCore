# Ultimate Odycer MMO Asset Foundation Specification

## Scope

This slice turns a local `.fovea` artifact into a content-addressed MMO asset
record that can be exchanged with an authoritative server. It does not add a
server, sign content, certify OpenXR hardware, or replace the existing
experimental HLOD, tile rasterizer, or multiplayer synchronization systems.

## Requirements

- Compute the SHA-256 digest from the exact `.fovea` bytes.
- Validate the canonical `FOVEA_3D` magic, v2 header, counts, AABB, payload,
  and optional-section ranges before publishing an asset record.
- Derive the stable network asset identifier as `sha256:<lowercase hex digest>`.
- Publish registry schema version `1.0.0` and the canonical `.fovea` binary
  format version from `FoveaBinaryFormat.VERSION`.
- Require MMO metadata for `owner_id`, `biome_id`, `physics_profile`, and
  `permissions`.
- Restrict physics profiles to `none`, `static`, `kinematic`, `dynamic`, or
  `soft_body`.
- Restrict permissions to `view`, `stream`, `interact`, `modify`, or `admin`.
- Mark immutable registry records as server-authoritative by default. This
  governs catalog metadata and download integrity, not mutable splat state,
  which remains owned by the Godot player client.
- Reject duplicate content-addressed IDs in one registry.
- Save and load the registry as JSON, failing closed on malformed content.
- Verify a downloaded file against both the recorded byte size and SHA-256.

## Non-goals

- Cryptographic signatures and key management.
- Server-side reconstruction or Zig2 transport implementation.
- Cross-client checkpoint exchange and conflict reconciliation.
- GPU, VR headset, latency, or packet-loss certification.
