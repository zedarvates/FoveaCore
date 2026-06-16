extends Node
class_name SplatBrushEngine

## Moteur d'interaction physique et creatif avec les Gaussian Splats
## Applique des modifications de couleur / opacite par zone spherique

signal brush_applied(splattable_path: NodePath, global_hit_position: Vector3, mode: int, radius: float, color: Color, opacity: float, flow_dir: Vector3)

enum BrushMode { PAINT, ERASE, RESTORE, FLOW, SCALE }

@export var brush_radius: float = 0.5
@export var brush_color: Color = Color(1.0, 0.0, 0.0)
@export var brush_mode: BrushMode = BrushMode.PAINT
@export var brush_opacity: float = 1.0
@export var brush_flow_direction := Vector3(1.0, 0.0, 0.0)
@export var brush_scale_factor: float = 1.2

var is_replicating: bool = false

# History for Undo/Redo
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _max_undo_depth: int = 20

var _current_stroke_splattable: FoveaSplattable = null
var _current_stroke_changes: Dictionary = {}
var _is_in_stroke: bool = false


func begin_stroke(splattable: FoveaSplattable) -> void:
	_current_stroke_splattable = splattable
	_current_stroke_changes.clear()
	_is_in_stroke = true
	_redo_stack.clear()

func commit_stroke() -> void:
	if not _is_in_stroke or _current_stroke_changes.is_empty():
		_is_in_stroke = false
		_current_stroke_splattable = null
		return
		
	var stroke_record = {
		"splattable": _current_stroke_splattable,
		"changes": _current_stroke_changes.duplicate(true)
	}
	_undo_stack.append(stroke_record)
	if _undo_stack.size() > _max_undo_depth:
		_undo_stack.remove_at(0)
		
	_is_in_stroke = false
	_current_stroke_splattable = null
	print("SplatBrushEngine: Stroke committed with %d splat changes." % stroke_record.changes.size())

func _record_splat_state(idx: int, splat: GaussianSplat) -> void:
	if not _current_stroke_changes.has(idx):
		_current_stroke_changes[idx] = {
			"color": { "old": splat.color, "new": splat.color },
			"opacity": { "old": splat.opacity, "new": splat.opacity },
			"normal": { "old": splat.normal, "new": splat.normal },
			"scale": { "old": splat.scale, "new": splat.scale }
		}

func _update_splat_new_state(idx: int, splat: GaussianSplat) -> void:
	if _current_stroke_changes.has(idx):
		var record = _current_stroke_changes[idx]
		record.color.new = splat.color
		record.opacity.new = splat.opacity
		record.normal.new = splat.normal
		record.scale.new = splat.scale

func undo() -> bool:
	if _undo_stack.is_empty():
		return false
		
	var stroke = _undo_stack.pop_back()
	var splattable = stroke.splattable
	if not is_instance_valid(splattable):
		return false
		
	for idx in stroke.changes:
		if idx < splattable.loaded_splats.size():
			var splat: GaussianSplat = splattable.loaded_splats[idx]
			var record = stroke.changes[idx]
			splat.color = record.color.old
			splat.opacity = record.opacity.old
			splat.normal = record.normal.old
			splat.scale = record.scale.old
			splat.palette_index = -1
			
	_redo_stack.append(stroke)
	_trigger_renderer_update(splattable)
	return true

func redo() -> bool:
	if _redo_stack.is_empty():
		return false
		
	var stroke = _redo_stack.pop_back()
	var splattable = stroke.splattable
	if not is_instance_valid(splattable):
		return false
		
	for idx in stroke.changes:
		if idx < splattable.loaded_splats.size():
			var splat: GaussianSplat = splattable.loaded_splats[idx]
			var record = stroke.changes[idx]
			splat.color = record.color.new
			splat.opacity = record.opacity.new
			splat.normal = record.normal.new
			splat.scale = record.scale.new
			splat.palette_index = -1
			
	_undo_stack.append(stroke)
	_trigger_renderer_update(splattable)
	return true

func _trigger_renderer_update(splattable: FoveaSplattable) -> void:
	if splattable.has_method("_update_local_renderer"):
		splattable.call("_update_local_renderer")
	for child in splattable.get_children():
		if child.has_method("render_splats"):
			child.render_splats(splattable.loaded_splats)

func apply_brush(node: Node3D, global_hit_position: Vector3) -> bool:
	if not node is FoveaSplattable:
		return false

	var splattable := node as FoveaSplattable
	if splattable.loaded_splats.is_empty():
		return false

	var local_hit := splattable.to_local(global_hit_position)
	var modified := false
	var dynamic_stroke := false

	# Start dynamic stroke if not already in one
	if not _is_in_stroke:
		begin_stroke(splattable)
		dynamic_stroke = true

	# Initialiser ou mettre à jour la grille spatiale
	if splattable.spatial_grid == null or not is_equal_approx(splattable.spatial_grid.cell_size, brush_radius):
		splattable.spatial_grid = FoveaSplattable.SplatSpatialHashGrid.new(brush_radius, splattable.loaded_splats)

	var indices: Array = splattable.spatial_grid.get_indices_in_radius(local_hit, brush_radius)

	for idx in indices:
		var splat: GaussianSplat = splattable.loaded_splats[idx]
		var splat_pos: Vector3 = splat.position
		if splat_pos.distance_to(local_hit) <= brush_radius:
			_record_splat_state(idx, splat)
			modified = true
			match brush_mode:
				BrushMode.PAINT:
					splat.color = brush_color
					splat.palette_index = -1  # Invalide le cache
				BrushMode.ERASE:
					splat.opacity = 0.0
				BrushMode.RESTORE:
					splat.opacity = clamp(brush_opacity, 0.0, 1.0)
				BrushMode.FLOW:
					# Stocker le courant de la rivière dans la propriété normal du splat
					splat.normal = brush_flow_direction.normalized()
				BrushMode.SCALE:
					# Modifier l'échelle du splat
					splat.scale *= brush_scale_factor
			_update_splat_new_state(idx, splat)

	if modified:
		_trigger_renderer_update(splattable)
		if not is_replicating:
			brush_applied.emit(splattable.get_path(), global_hit_position, brush_mode, brush_radius, brush_color, brush_opacity, brush_flow_direction)

	if dynamic_stroke:
		commit_stroke()

	return modified

