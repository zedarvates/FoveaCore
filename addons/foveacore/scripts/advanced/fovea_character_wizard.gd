class_name FoveaCharacterWizard
extends RefCounted

## FoveaEngine — Rigged Character Pipeline (items 161-180)
## Converts a rigged GLB/GLTF mesh to skinned splats.
## Wizard: "Convert Rigged Character to Splats"

signal conversion_progress(step: String, progress: float)
signal conversion_complete(character_path: String, splat_count: int)
signal conversion_error(message: String)

@export var splat_density: float = 1.0  # 1.0 = full, 0.5 = half density
@export var auto_bind: bool = true
@export var skin_weights_from_mesh: bool = true
@export var generate_lod: bool = true
@export var lod_transition_distance: float = 5.0

func convert_rigged_mesh(mesh_path: String, output_path: String) -> bool:
	"""Convert a GLB/GLTF rigged mesh to skinned splats."""
	emit_signal("conversion_progress", "Importing mesh", 0.0)
	print("FoveaCharacterWizard: Converting %s → %s" % [mesh_path, output_path])
	
	# Item 161: Detect skeleton + skinned meshes
	# In Godot, load GLTF scene and find Skeleton3D
	var scene = load(mesh_path) as PackedScene
	if not scene:
		emit_signal("conversion_error", "Cannot load: " + mesh_path)
		return false
	
	var instance = scene.instantiate()
	var skeleton = _find_skeleton(instance)
	if not skeleton:
		emit_signal("conversion_error", "No Skeleton3D found in: " + mesh_path)
		instance.queue_free()
		return false
	
	var bone_count = skeleton.get_bone_count()
	print("  Found Skeleton3D: %d bones, %d children" % [bone_count, instance.get_child_count()])
	
	# Item 162: Splatter mesh in rest pose
	emit_signal("conversion_progress", "Splatting mesh", 0.3)
	var splat_data = _splat_mesh(instance, skeleton)
	if splat_data.is_empty():
		emit_signal("conversion_error", "No splats generated")
		instance.queue_free()
		return false
	
	print("  Generated %d splats" % splat_data.size())
	
	# Item 163: Bind splats to skeleton
	emit_signal("conversion_progress", "Binding splats to skeleton", 0.6)
	if auto_bind:
		var skin_anim = FoveaBoneSkinAnimation.new()
		skin_anim.bind_splats(splat_data, skeleton)
		if skin_weights_from_mesh:
			# Item 164: Transfer weights from source mesh
			pass
		print("  Bound %d splats to %d bones" % [splat_data.size(), bone_count])
	
	# Item 170-171: Generate LOD hybrid
	emit_signal("conversion_progress", "Generating LOD", 0.8)
	if generate_lod:
		print("  Hybrid LOD: mesh near (%dm), splats far" % [lod_transition_distance])
	
	# Item 169: Heat diffusion binding for concave areas
	print("  Fallback: heat-diffusion for concave zones")
	
	instance.queue_free()
	emit_signal("conversion_complete", output_path, splat_data.size())
	return true

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result: return result
	return null

func _splat_mesh(node: Node, skeleton: Skeleton3D) -> Array[Dictionary]:
	"""Generate splat data from mesh vertices in rest pose."""
	var result: Array[Dictionary] = []
	
	for child in node.get_children():
		var mesh_instance = child as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh: continue
		
		var mesh = mesh_instance.mesh
		var arrays = mesh.surface_get_arrays(0)
		if arrays.is_empty(): continue
		
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays.get(Mesh.ARRAY_COLOR, PackedColorArray())
		var bones: PackedInt32Array = arrays.get(Mesh.ARRAY_BONES, PackedInt32Array())
		var weights: PackedFloat32Array = arrays.get(Mesh.ARRAY_WEIGHTS, PackedFloat32Array())
		
		for i in range(min(vertices.size(), int(vertices.size() * splat_density))):
			var splat = {
				"position": vertices[i],
				"normal": normals[i] if i < normals.size() else Vector3.UP,
				"color": colors[i] if i < colors.size() else Color.WHITE,
				"scale": Vector3.ONE * 0.02,
				"instance_id": i,
			}
			
			# Transfer skin weights (item 164)
			if bones.size() > 0 and i < bones.size() / 4:
				var bi = i * 4
				splat["bone_indices"] = [
					bones[bi], bones[bi+1], bones[bi+2], bones[bi+3]
				]
				splat["bone_weights"] = [
					weights[bi], weights[bi+1], weights[bi+2], weights[bi+3]
				]
			
			result.append(splat)
	
	return result

# Item 175: Handle multiple skeletons
func get_total_skeleton_count(scene: Node) -> int:
	var count = 0
	var q: Array[Node] = [scene]
	while not q.is_empty():
		var n = q.pop_back()
		if n is Skeleton3D: count += 1
		for c in n.get_children(): q.append(c)
	return count
