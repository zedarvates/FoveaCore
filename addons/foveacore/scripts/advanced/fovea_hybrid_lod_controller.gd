@tool
class_name FoveaHybridLODController
extends Node3D

## FoveaHybridLODController — Manages transitions between 3DGS and simplified meshes
##
## Renders high-fidelity Gaussian Splats when close, and transitions to
## a simplified MeshFlow mesh at medium/long distances to optimize performance and prevent aliasing.

@export_group("LOD Targets")
## The high-fidelity splat node used at close range.
@export var splattable: FoveaSplattable = null:
	set(val):
		splattable = val
		_update_references()

## The MeshInstance3D node representing the simplified mesh used at far range.
@export var mesh_instance: MeshInstance3D = null:
	set(val):
		mesh_instance = val
		_update_references()

## Optional LOD stretch animator node to modulate splat scale near transition boundary.
@export var lod_stretch_animator: FoveaLodStretchAnimator = null

@export_group("LOD Settings")
## Distance (in meters) at which the renderer switches from Gaussian Splats to the simplified mesh.
@export var transition_distance: float = 12.0

## The check interval in seconds to run camera distance evaluations (prevents checking every frame).
@export var evaluation_interval: float = 0.1

@export_group("MeshFlow Assets")
## Path to the pre-generated MeshFlow GLB containing simplified LOD meshes.
@export_file("*.glb") var meshflow_glb_path: String = "":
	set(val):
		meshflow_glb_path = val
		if is_node_ready() and not meshflow_glb_path.is_empty():
			_load_meshflow_lod_mesh()

@export_group("Textured LOD Settings")
## The shared texture atlas containing all packed LOD textures.
@export var lod_texture_atlas: Texture2D = null:
	set(val):
		lod_texture_atlas = val
		_update_references()

## The UV region within the atlas for this controller's mesh.
@export var lod_texture_region: Rect2 = Rect2(0, 0, 1, 1):
	set(val):
		lod_texture_region = val
		_update_references()

var _timer: float = 0.0
var _current_lod: int = -1 # 0 = Splat (close), 1 = Mesh (far)

func _ready() -> void:
	if not Engine.is_editor_hint():
		_ensure_nodes()
		_load_meshflow_lod_mesh()
		_evaluate_lod(true) # Force initial evaluation

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	_timer += delta
	if _timer >= evaluation_interval:
		_timer = 0.0
		_evaluate_lod()

func _ensure_nodes() -> void:
	if splattable == null:
		splattable = get_node_or_null("FoveaSplattable") as FoveaSplattable
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D

func _update_references() -> void:
	if is_node_ready():
		_evaluate_lod(true)

func _load_meshflow_lod_mesh() -> void:
	if meshflow_glb_path.is_empty() or mesh_instance == null:
		return
		
	if not ResourceLoader.exists(meshflow_glb_path):
		push_warning("FoveaHybridLODController: MeshFlow GLB not found at: " + meshflow_glb_path)
		return
		
	var glb = load(meshflow_glb_path)
	if glb:
		var scene = glb.instantiate()
		var lod_mesh: Mesh = null
		
		# Traverse scene to extract the first available mesh (LOD 1 or LOD 2 from MeshFlow)
		for child in scene.get_children():
			if child is MeshInstance3D:
				lod_mesh = child.mesh
				break
				
		if lod_mesh != null:
			mesh_instance.mesh = lod_mesh
			print("FoveaHybridLODController: Successfully loaded MeshFlow LOD mesh from GLB.")
		else:
			push_error("FoveaHybridLODController: No Mesh found in GLB: " + meshflow_glb_path)
		scene.queue_free()

func _evaluate_lod(force: bool = false) -> void:
	if splattable == null or mesh_instance == null:
		return
		
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
		
	var dist := global_position.distance_to(camera.global_position)
	var target_lod := 0 # Default to Splat

	if lod_stretch_animator != null and transition_distance > 0.0:
		var dist_ratio := clampf(dist / transition_distance, 0.0, 1.0)
		lod_stretch_animator.amplitude = lerpf(0.0, 0.25, dist_ratio)
	
	if dist >= transition_distance:
		target_lod = 1 # Switch to Mesh
		
	if target_lod != _current_lod or force:
		_current_lod = target_lod
		_apply_lod_state()

func _apply_lod_state() -> void:
	if _current_lod == 0:
		# Close range: Enable Gaussian Splats, disable simplified mesh
		splattable.splatting_enabled = true
		splattable.visible = true
		mesh_instance.visible = false
		
		# Show original mesh if needed, but FoveaSplattable handles hiding it
		if splattable.hide_mesh_when_splatting:
			if splattable.get("_mesh_instance_ref") != null:
				splattable.get("_mesh_instance_ref").visible = false
				
		print("FoveaHybridLODController: Switch to LOD 0 (Gaussian Splats)")
	else:
		# Far range: Disable Gaussian Splats, enable simplified mesh
		splattable.splatting_enabled = false
		splattable.visible = false
		mesh_instance.visible = true
		
		if lod_texture_atlas != null and mesh_instance != null:
			var mat = mesh_instance.material_override
			if not mat is StandardMaterial3D:
				mat = StandardMaterial3D.new()
				mesh_instance.material_override = mat
			
			mat.albedo_texture = lod_texture_atlas
			mat.uv1_scale = Vector3(lod_texture_region.size.x, lod_texture_region.size.y, 1.0)
			mat.uv1_offset = Vector3(lod_texture_region.position.x, lod_texture_region.position.y, 0.0)
		
		print("FoveaHybridLODController: Switch to LOD 1 (Simplified MeshFlow Mesh)")
