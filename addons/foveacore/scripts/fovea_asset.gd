@tool
extends Resource
class_name FoveaAsset
## A compiled, compressed Gaussian Splatting scene loaded from a [code].fovea[/code] file.
##
## [b]FoveaAsset[/b] is the in-memory representation of FoveaEngine's native binary
## format. It holds the splat buffer plus the codebooks needed to decode it
## (color palette, anisotropic covariance codebook), an optional visual style and
## proxy mesh, and free-form JSON metadata from training/compression.
##
## You normally never build one by hand: assign a [code].fovea[/code] path to a
## [FoveaSplat3D] node, or load it as a resource:
## [codeblock]
## var asset: FoveaAsset = load("res://assets/garden.fovea")
## print("%d splats, AABB %s" % [asset.splat_count, asset.get_aabb()])
## [/codeblock]
##
## @tutorial: see plans/PHASE0_FONDATION_TASKS.md (Phase 0 — Fondation)

## Total number of Gaussian splats packed in [member splats_raw_bytes].
@export var splat_count: int = 0

## Number of entries in the vector-quantized color palette (typically 256).
@export var color_codebook_size: int = 0

## Number of entries in the precomputed covariance codebook (typically 1024).
@export var covar_codebook_size: int = 0

## Minimum corner of the asset's axis-aligned bounding box, in local space.
@export var aabb_min: Vector3 = Vector3.ZERO

## Maximum corner of the asset's axis-aligned bounding box, in local space.
@export var aabb_max: Vector3 = Vector3.ZERO

## Vector-quantized color palette used to decode per-splat 8-bit color indices.
@export var color_palette: FoveaColorPalette = null

## Precomputed scale/rotation (covariance) codebook. Each splat stores an index
## into this table instead of a full 3x3 matrix, for compact storage.
@export var covariance_codebook: PackedByteArray = PackedByteArray()

## Raw packed splat stream (positions, color indices, covariance indices, opacity).
## Decoded on the GPU via the native loader; treat as opaque binary.
@export var splats_raw_bytes: PackedByteArray = PackedByteArray()

## Optional artistic style baked with the asset (null inherits the global
## FoveaCoreManager style).
@export var style: FoveaStyle = null

## Optional polygonal proxy mesh (e.g. for collisions or low-end fallback).
@export var mesh: ArrayMesh = null

## Free-form metadata embedded in the file header (training parameters,
## compression ratios, session name, timestamps...).
@export var metadata: Dictionary = {}

## Optional flipbook frame index for dynamic 4D splat sequences.
@export var flipbook_frame: int = 0

## Total frame count in the flipbook sequence (0 if static).
@export var flipbook_frame_count: int = 0


## Returns the asset's local-space bounding box built from [member aabb_min]
## and [member aabb_max].
func get_aabb() -> AABB:
	return AABB(aabb_min, aabb_max - aabb_min)
