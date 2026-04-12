extends MultiMeshInstance3D
class_name PointCloudVisualizer

## PointCloudVisualizer — Renders high-density point clouds in Godot
## Uses MultiMeshInstance3D for performance (millions of points)

@export var point_size: float = 0.02
@export var default_color: Color = Color.WHITE

func load_from_ply(path: String) -> void:
    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("PointCloudVisualizer: Could not open PLY: ", path)
        return
        
    var header = _parse_ply_header(file)
    if header.vertex_count == 0:
        return
        
    _setup_multimesh(header.vertex_count)
    _populate_points(file, header)

func _setup_multimesh(count: int) -> void:
    var mm = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.instance_count = count
    
    # Use a QuadMesh (plane) for better splat-like visualization
    var mesh = QuadMesh.new()
    mesh.size = Vector2(point_size, point_size)
    
    # Enable billboarding so planes face the camera
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
            header.vertex_count = line.split(" ")[2].to_int()
        if line.begins_with("property uchar red"):
            header.has_color = true
        if line == "end_header":
            break
    return header

func _populate_points(file: FileAccess, header: Dictionary) -> void:
	# Note: This is a basic ASCII PLY reader for the prototype
	for i in range(header.vertex_count):
		var pos = Vector3.ZERO
		var color = default_color
		
		if file != null and not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.is_empty():
				continue
				
			var parts = line.split(" ")
			if parts.size() >= 3:
				pos = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
				
				if header.has_color and parts.size() >= 6:
					color = Color(
						parts[3].to_float() / 255.0,
						parts[4].to_float() / 255.0,
						parts[5].to_float() / 255.0
					)
		else:
			# Fallback for preview or missing file
			pos = Vector3(randf_range(-1,1), randf_range(0,2), randf_range(-1,1))
			color = Color(randf(), randf(), randf())
			
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
		multimesh.set_instance_color(i, color)
	
	print("PointCloudVisualizer: Visualized ", header.vertex_count, " points.")
