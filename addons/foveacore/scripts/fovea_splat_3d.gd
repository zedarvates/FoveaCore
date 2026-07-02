@tool
extends Node3D
## The main scene node of FoveaEngine — drop it in a scene, assign a splat file, done.
##
## [b]FoveaSplat3D[/b] is the public, stable entry point for rendering Gaussian
## Splatting assets ([code].fovea[/code], [code].ply[/code], [code].spz[/code]) in Godot.
## It exposes only the essential properties; everything advanced (styles, overrides,
## instancing, morphs) lives on the internal [FoveaSplattable] delegate, reachable
## through [method get_advanced].
##
## [codeblock]
## var splat := FoveaSplat3D.new()
## splat.source_path = "res://assets/garden.fovea"
## add_child(splat)
## [/codeblock]

class_name FoveaSplat3D

## Emitted after the source asset has been (re)loaded into the renderer.
signal asset_loaded(path: String)

## Rendering quality presets. [constant AUTO] picks a profile from the global
## FoveaCoreManager settings; the others force a density/culling trade-off.
enum QualityPreset {
	AUTO,        ## Inherit global settings (default).
	PERFORMANCE, ## Lower density, aggressive culling — mobile / standalone VR.
	BALANCED,    ## Full density, standard culling — desktop.
	CINEMATIC,   ## Maximum density, conservative culling — offline capture / Movie Maker.
}

## Path to the Gaussian Splatting asset to render ([code].fovea[/code] native,
## [code].ply[/code] 3DGS training output, [code].splat[/code] binary, or [code].spz[/code]).
@export_file("*.fovea", "*.ply", "*.splat", "*.spz") var source_path: String = "":
	set(val):
		source_path = val
		_apply_source_path()

## Master switch for this asset's rendering.
@export var enabled: bool = true:
	set(val):
		enabled = val
		_apply_enabled()

## Quality/performance trade-off applied to this asset.
@export var quality_preset: QualityPreset = QualityPreset.AUTO:
	set(val):
		quality_preset = val
		_apply_quality_preset()

## If [code]true[/code], generates a static physics collision body from the splat
## volume on load (requires a [code].fovea[/code] source).
@export var generate_collisions: bool = false:
	set(val):
		generate_collisions = val
		if _splattable != null:
			_splattable.generate_collisions = val

## Opacity multiplier applied to every splat of this asset (0.0 to 1.0).
@export_range(0.0, 1.0) var opacity: float = 1.0:
	set(val):
		opacity = val
		if _splattable != null:
			_splattable.alpha_override = val

## If [code]true[/code], this asset is treated as completely static/stable.
## Static assets bypass redundant GPU culling/sorting dispatches on mobile.
## Dynamic assets support skeletal skinning, physics solver, and get sorted every frame.
@export var is_static: bool = true:
	set(val):
		is_static = val
		if _splattable != null:
			_splattable.is_static = val


## Internal delegate doing the actual loading/rendering. Created at runtime,
## never persisted into the scene file.
var _splattable: FoveaSplattable = null


func _ready() -> void:
	_ensure_splattable()
	_apply_all()


## Returns the internal [FoveaSplattable] delegate for advanced configuration
## (styles, per-instance overrides, instancing, segmentation...).
## Returns [code]null[/code] before the node is ready.
func get_advanced() -> FoveaSplattable:
	return _splattable


## Converts the currently loaded splats to a compressed native [code].fovea[/code]
## asset written at [param dest_path]. Returns [code]true[/code] on success.
func export_to_fovea(dest_path: String) -> bool:
	if _splattable == null:
		push_error("FoveaSplat3D: Node not ready, cannot export.")
		return false
	return _splattable.export_to_fovea(dest_path)


func _ensure_splattable() -> void:
	if _splattable != null:
		return
	_splattable = get_node_or_null("FoveaSplattableInternal") as FoveaSplattable
	if _splattable != null:
		return
	_splattable = FoveaSplattable.new()
	_splattable.name = "FoveaSplattableInternal"
	# No owner assignment: the delegate stays runtime-only and is never saved.
	add_child(_splattable)


func _apply_all() -> void:
	if _splattable == null:
		return
	_splattable.generate_collisions = generate_collisions
	_splattable.alpha_override = opacity
	_splattable.is_static = is_static
	_apply_quality_preset()
	_apply_enabled()
	_apply_source_path()


func _apply_source_path() -> void:
	if _splattable == null or not is_node_ready():
		return
	if _splattable.splat_file_path == source_path:
		return
	_splattable.splat_file_path = source_path
	if not source_path.is_empty():
		asset_loaded.emit(source_path)


func _apply_enabled() -> void:
	if _splattable == null:
		return
	_splattable.splatting_enabled = enabled
	_splattable.visible = enabled


func _apply_quality_preset() -> void:
	if _splattable == null:
		return
	match quality_preset:
		QualityPreset.PERFORMANCE:
			_splattable.splat_density = 0.5
			_splattable.culling_priority = 3
		QualityPreset.BALANCED:
			_splattable.splat_density = 1.0
			_splattable.culling_priority = 5
		QualityPreset.CINEMATIC:
			_splattable.splat_density = 2.0
			_splattable.culling_priority = 9
		_:
			# AUTO — leave the delegate's defaults so global settings apply.
			pass
