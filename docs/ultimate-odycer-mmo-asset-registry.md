# Ultimate Odycer MMO Asset Registry

`FoveaAssetRegistry` gives `.fovea` files a stable, content-addressed identity
and the minimum metadata needed at an authoritative MMO boundary. The binary
asset format remains version 2; the registry is a separate versioned JSON
contract.

Registry creation fails closed unless the source is a structurally valid
`FOVEA_3D` v2 container. Renaming arbitrary bytes to `.fovea` is rejected
before the SHA-256 identity is published.

## Authority boundary

The intended flow is:

1. The reconstruction/baking service writes and validates a `.fovea` file.
2. The server calls `FoveaAssetRegistry.build_entry()` with server-owned MMO
   metadata.
3. The server stores the returned entry in a registry built with
   `build_registry()` and distributes an immutable content reference.
4. A client downloads the asset but does not choose its ID, owner, permissions,
   physics profile, or authority model.
5. Before loading, both server and client call `verify_asset_file()`. A byte-size
   or SHA-256 mismatch rejects the artifact.

This establishes integrity and identity, not authenticity. A production
distribution layer must additionally sign the registry or deliver it through
an authenticated server channel. Client-provided registry metadata must never
be trusted as an authorization decision.

## Godot example

```gdscript
const FoveaAssetRegistry := preload(
    "res://addons/foveacore/scripts/network/fovea_asset_registry.gd"
)

var result: Dictionary = FoveaAssetRegistry.build_entry(
    "res://assets/velorath_crystal.fovea",
    {
        "owner_id": "realm:ultimate-odycer",
        "biome_id": "velorath",
        "physics_profile": "static",
        "permissions": ["view", "stream", "interact"],
        "source_uri": "registry://velorath/crystal-cluster-a",
    }
)
if not result["ok"]:
    push_error(result["error"])
    return

var registry_result: Dictionary = FoveaAssetRegistry.build_registry(
    [result["entry"]]
)
if registry_result["ok"]:
    FoveaAssetRegistry.save_registry(
        "user://ultimate_odycer_fovea_registry.json",
        registry_result["registry"]
    )
```

## JSON contract

```json
{
  "schema_version": "1.0.0",
  "kind": "fovea.mmo_asset_registry",
  "assets": [
    {
      "schema_version": "1.0.0",
      "asset_id": "sha256:<64 lowercase hexadecimal characters>",
      "content": {
        "format": "fovea",
        "format_version": 2,
        "hash_algorithm": "sha256",
        "sha256": "<64 lowercase hexadecimal characters>",
        "bytes": 123456
      },
      "mmo": {
        "owner_id": "realm:ultimate-odycer",
        "biome_id": "velorath",
        "physics_profile": "static",
        "permissions": ["interact", "stream", "view"],
        "authority_model": "server_authoritative"
      },
      "source": {
        "uri": "registry://velorath/crystal-cluster-a"
      }
    }
  ]
}
```

Allowed physics profiles are `none`, `static`, `kinematic`, `dynamic`, and
`soft_body`. Allowed permissions are `view`, `stream`, `interact`, `modify`,
and `admin`. Unknown values fail closed.

## Explicitly outside this slice

- Registry signatures and key rotation.
- Zig2 storage, transport, interest management, and delta synchronization.
- Per-splat network IDs, deterministic sculpting, rollback, and reconciliation.
- GPU residency budgets and asynchronous render queues.
- GPU, OpenXR headset, latency, packet-loss, or MMO-scale certification.

The repository already contains experimental HLOD/MIP-style selection, tile
rasterization, and an authority-mediated multiplayer sync layer. Their existing
hardware and integration gates remain separate from this registry contract.

Per-splat sparse changes use the separate, transport-neutral
[Splat Delta Protocol v1](ultimate-odycer-splat-delta-protocol.md). Its
content-addressed identity is shared with this registry, while its revision and
compression rules remain independent of registry persistence.
