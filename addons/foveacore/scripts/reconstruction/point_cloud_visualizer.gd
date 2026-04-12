extends MultiMeshInstance3D
class_name PointCloudVisualizer

## PointCloudVisualizer — Rendu haute densité de nuages de points
## Utilise MultiMeshInstance3D pour la performance

@export var point_size: float = 0.02
@export var default_color: Color = Color.WHITE

func load_from_ply(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("PointCloudVisualizer: Fichier PLY introuvable: ", path)
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
		
	var header = _parse_ply_header(file)
	var count = header.get("vertex_count", 0)
	if count == 0:
		return
		
	_setup_multimesh(count)
	_populate_points(file, header)

func _setup_multimesh(count: int) -> void:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = count
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(point_size, point_size)
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.use_point_size = true
	mesh.material = mat
	
	mm.mesh = mesh
	self.multimesh = mm

func _parse_ply_header(file: FileAccess) -> Dictionary:
	var header = {"vertex_count": 0, "has_color": false}
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("element vertex"):
			var parts = line.split(" ")
			if parts.size() >= 3:
				header["vertex_count"] = int(parts[2])
		if line.contains("property") and (line.contains("red") or line.contains("f_dc")):
			header["has_color"] = true
		if line == "end_header":
			break
	return header

func _populate_points(file: FileAccess, header: Dictionary) -> void:
	var count = header.get("vertex_count", 0)
	var has_color = header.get("has_color", false)
	
	for i in range(count):
		var pos = Vector3.ZERO
		var color = default_color
		
		if file != null and not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.is_empty(): continue
				
			var parts = line.split(" ")
			if parts.size() >= 3:
				pos = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				if has_color and parts.size() >= 6:
					color = Color(float(parts[3])/255.0, float(parts[4])/255.0, float(parts[5])/255.0)
		else:
			pos = Vector3(randf_range(-1,1), randf_range(0,2), randf_range(-1,1))
			color = Color(randf(), randf(), randf())
			
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
		multimesh.set_instance_color(i, color)
	
	print("PointCloudVisualizer: Affichage de %d points." % count)
