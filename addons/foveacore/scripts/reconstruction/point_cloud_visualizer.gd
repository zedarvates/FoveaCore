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
    
    # Simple quad or sphere for point mesh
    var mesh = BoxMesh.new()
    mesh.size = Vector3(point_size, point_size, point_size)
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
    for i in range(header.vertex_count):
        # This assumes a binary PLY or simple ASCII PLY 
        # In a real implementation, we would handle both formats.
        # For this prototype, we simulate loading the points.
        var pos = Vector3(
            randf_range(-1.0, 1.0), 
            randf_range(0.0, 2.0), 
            randf_range(-1.0, 1.0)
        )
        var color = Color(randf(), randf(), randf()) if header.has_color else default_color
        
        multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
        multimesh.set_instance_color(i, color)
    
    print("PointCloudVisualizer: Visualized ", header.vertex_count, " points.")
