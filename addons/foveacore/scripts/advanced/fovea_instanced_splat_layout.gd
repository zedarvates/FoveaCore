class_name FoveaInstancedSplatLayout
extends RefCounted

## Runtime-only layout produced by gpu_culling_instanced.glsl.
## The first 16 bytes are always the canonical serialized .fovea splat record.
const CANONICAL_SPLAT_BYTE_SIZE: int = 16
const LEGACY_OUTPUT_SPLAT_BYTE_SIZE: int = 20
const OUTPUT_SPLAT_BYTE_SIZE: int = 24
const LOCAL_IDX_OFFSET: int = 16
const INSTANCE_ID_OFFSET: int = 20
