extends Resource
class_name FoveaAsset

## FoveaAsset — Custom Resource for .fovea assets
## Holds all parsed components of a compiled Gaussian Splat scene, including:
## - Splats (PackedSplat binary buffer)
## - Color Palette and Anisotropic Covariance Codebook
## - Optional visual style parameters and polygonal meshes
## - Custom JSON metadata

@export var splat_count: int = 0
@export var color_codebook_size: int = 0
@export var covar_codebook_size: int = 0
@export var aabb_min: Vector3 = Vector3.ZERO
@export var aabb_max: Vector3 = Vector3.ZERO
@export var color_palette: FoveaColorPalette = null
@export var covariance_codebook: PackedByteArray = PackedByteArray()
@export var splats_raw_bytes: PackedByteArray = PackedByteArray()
@export var style: FoveaStyle = null
@export var mesh: ArrayMesh = null
@export var metadata: Dictionary = {}
