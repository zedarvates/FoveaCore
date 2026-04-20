extends Node
class_name ColmapSparseImporter

signal import_started()
signal import_progress(message: String, percent: float)
signal import_completed(points: Array, cameras: Array, images: Array)
signal import_failed(reason: String)

class SparsePoint:
	var position: Vector3
	var color: Color
	var track: Array[int]
	var error: float

class SparseCamera:
	var model: String
	var width: int
	var height: int
	var fx: float
	var fy: float
	var cx: float
	var cy: float
	var k1: float = 0.0
	var k2: float = 0.0

class SparseImage:
	var camera_id: int
	var filename: String
	var rotation: Basis
	var translation: Vector3

func import_from_colmap(colmap_dir: String) -> bool:
	import_started.emit()
	
	var points: Array[SparsePoint] = []
	var cameras: Array[SparseCamera] = []
	var images: Array[SparseImage] = []
	
	import_progress.emit("Parsing cameras...", 20)
	_cameras_file(colmap_dir + "/cameras.bin", cameras)
	
	import_progress.emit("Parsing images...", 50)
	_images_file(colmap_dir + "/images.bin", images)
	
	import_progress.emit("Parsing points...", 80)
	_points_file(colmap_dir + "/points3D.bin", points)
	
	if points.is_empty():
		import_failed.emit("No 3D points found in COLMAP data")
		return false
	
	import_progress.emit("Import complete", 100)
	import_completed.emit(points, cameras, images)
	return true

func _cameras_file(path: String, cameras: Array[SparseCamera]) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ColmapSparseImporter: cameras.bin not found")
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var num_cameras = file.get_32()
	
	var camera_models = ["SIMPLE_PINHOLE", "PINHOLE", "SIMPLE_RADIAL", "RADIAL", "OPENCV", "FULL_OPENCV"]
	
	for i in range(num_cameras):
		var cam = SparseCamera.new()
		var model_id = file.get_32()
		cam.model = camera_models[model_id] if model_id < camera_models.size() else "UNKNOWN"
		cam.width = file.get_32()
		cam.height = file.get_32()
		cam.fx = file.get_double()
		cam.fy = file.get_double()
		cam.cx = file.get_double()
		cam.cy = file.get_double()
		
		if model_id >= 3:
			cam.k1 = file.get_double()
			cam.k2 = file.get_double()
		
		cameras.append(cam)
	
	file.close()

func _images_file(path: String, images: Array[SparseImage]) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ColmapSparseImporter: images.bin not found")
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var num_images = file.get_32()
	
	for i in range(num_images):
		var img = SparseImage.new()
		var qw = file.get_double()
		var qx = file.get_double()
		var qy = file.get_double()
		var qz = file.get_double()
		img.rotation = Basis(Quaternion(qx, qy, qz, qw))
		
		img.translation = Vector3(file.get_double(), file.get_double(), file.get_double())
		img.camera_id = file.get_32()
		
		var name_len = file.get_32()
		var filename = ""
		for j in range(name_len):
			filename += char(file.get_8())
		img.filename = filename
		
		images.append(img)
	
	file.close()

func _points_file(path: String, points: Array[SparsePoint]) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ColmapSparseImporter: points3D.bin not found")
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var num_points = file.get_64()
	
	for i in range(num_points):
		var pt = SparsePoint.new()
		pt.position = Vector3(file.get_double(), file.get_double(), file.get_double())
		pt.color = Color(
			file.get_float() / 255.0,
			file.get_float() / 255.0,
			file.get_float() / 255.0
		)
		
		var track_len = file.get_64()
		for j in range(track_len):
			pt.track.append(file.get_32())
		
		pt.error = file.get_double()
		points.append(pt)
	
	file.close()

func convert_to_ply_format(points: Array[SparsePoint]) -> String:
	var ply = "ply\n"
	ply += "format ascii 1.0\n"
	ply += "element vertex %d\n" % points.size()
	ply += "property float x\n"
	ply += "property float y\n"
	ply += "property float z\n"
	ply += "property uchar red\n"
	ply += "property uchar green\n"
	ply += "property uchar blue\n"
	ply += "end_header\n"
	
	for pt in points:
		ply += "%.4f %.4f %.4f %d %d %d\n" % [
			pt.position.x, pt.position.y, pt.position.z,
			int(pt.color.r * 255), int(pt.color.g * 255), int(pt.color.b * 255)
		]
	
	return ply

func get_camera_positions(images: Array[SparseImage]) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for img in images:
		positions.append(-img.rotation.inverse() * img.translation)
	return positions

func export_to_star_workspace(colmap_dir: String, output_dir: String) -> bool:
	var points: Array[SparsePoint] = []
	var cameras: Array[SparseCamera] = []
	var images: Array[SparseImage] = []
	
	if not import_from_colmap(colmap_dir):
		return false
	
	import_progress.emit("Converting to STAR workspace...", 50)
	
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	
	var ply_content = convert_to_ply_format(points)
	var ply_file = FileAccess.open(output_dir + "/point_cloud.ply", FileAccess.WRITE)
	ply_file.store_string(ply_content)
	ply_file.close()
	
	var metadata = {
		"format": "star_workspace",
		"colmap_source": colmap_dir,
		"point_count": points.size(),
		"camera_count": cameras.size(),
		"image_count": images.size(),
		"camera_positions": get_camera_positions(images).map(func(p): return [p.x, p.y, p.z])
	}
	
	var json_file = FileAccess.open(output_dir + "/colmap_metadata.json", FileAccess.WRITE)
	json_file.store_string(JSON.stringify(metadata, "\t"))
	json_file.close()
	
	import_progress.emit("STAR workspace created", 100)
	return true