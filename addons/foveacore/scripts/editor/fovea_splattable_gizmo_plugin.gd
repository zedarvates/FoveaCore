@tool
extends EditorNode3DGizmoPlugin

## FoveaSplatGizmoPlugin — Custom 3D gizmo plugin to visualize FoveaSplattable nodes in the viewport.
## Draws Node AABB and custom indicators representing culling priority and splat density.

const FoveaSplattableScript = preload("res://addons/foveacore/scripts/fovea_splattable.gd")

func _get_gizmo_name() -> String:
	return "FoveaSplattable"

func _has_gizmo(node: Node3D) -> bool:
	return node is FoveaSplattable

func _init() -> void:
	create_material("priority_low", Color(1.0, 0.3, 0.2, 0.7))    # Red (priority 0-3)
	create_material("priority_medium", Color(0.2, 0.8, 0.4, 0.7)) # Green (priority 4-7)
	create_material("priority_high", Color(0.2, 0.6, 1.0, 0.7))   # Blue (priority 8-10)
	create_material("density_indicator", Color(1.0, 0.9, 0.2, 0.9)) # Yellow

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node = gizmo.get_node_3d() as FoveaSplattable
	if not node:
		return
		
	var aabb: AABB = node.get_aabb()
	var pos := aabb.position
	var size := aabb.size
	
	# Draw Bounding Box lines
	var lines := PackedVector3Array()
	
	# Bottom face
	lines.append(pos)
	lines.append(pos + Vector3(size.x, 0, 0))
	lines.append(pos + Vector3(size.x, 0, 0))
	lines.append(pos + Vector3(size.x, 0, size.z))
	lines.append(pos + Vector3(size.x, 0, size.z))
	lines.append(pos + Vector3(0, 0, size.z))
	lines.append(pos + Vector3(0, 0, size.z))
	lines.append(pos)
	
	# Top face
	var top := pos + Vector3(0, size.y, 0)
	lines.append(top)
	lines.append(top + Vector3(size.x, 0, 0))
	lines.append(top + Vector3(size.x, 0, 0))
	lines.append(top + Vector3(size.x, 0, size.z))
	lines.append(top + Vector3(size.x, 0, size.z))
	lines.append(top + Vector3(0, 0, size.z))
	lines.append(top + Vector3(0, 0, size.z))
	lines.append(top)
	
	# Vertical pillars
	lines.append(pos)
	lines.append(top)
	lines.append(pos + Vector3(size.x, 0, 0))
	lines.append(top + Vector3(size.x, 0, 0))
	lines.append(pos + Vector3(size.x, 0, size.z))
	lines.append(top + Vector3(size.x, 0, size.z))
	lines.append(pos + Vector3(0, 0, size.z))
	lines.append(top + Vector3(0, 0, size.z))
	
	# Choose material based on culling priority
	var priority = node.culling_priority
	var mat_name = "priority_medium"
	if priority <= 3:
		mat_name = "priority_low"
	elif priority >= 8:
		mat_name = "priority_high"
		
	var mat = get_material(mat_name, gizmo)
	gizmo.add_lines(lines, mat, false)
	
	# Draw splat density indicator at the top center of the AABB
	var center = aabb.get_center()
	var indicator_pos = center + Vector3(0, size.y * 0.5 + 0.1, 0)
	var density_lines := PackedVector3Array()
	var indicator_radius = clamp(node.splat_density * 0.1, 0.02, 0.5)
	
	density_lines.append(indicator_pos + Vector3(-indicator_radius, 0, 0))
	density_lines.append(indicator_pos + Vector3(indicator_radius, 0, 0))
	density_lines.append(indicator_pos + Vector3(0, -indicator_radius, 0))
	density_lines.append(indicator_pos + Vector3(0, indicator_radius, 0))
	density_lines.append(indicator_pos + Vector3(0, 0, -indicator_radius))
	density_lines.append(indicator_pos + Vector3(0, 0, indicator_radius))
	
	var density_mat = get_material("density_indicator", gizmo)
	gizmo.add_lines(density_lines, density_mat, false)
