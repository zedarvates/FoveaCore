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
	
	var num_cameras = file.get_64() # COLMAP uses uint64_t
	
	var camera_models = ["SIMPLE_PINHOLE", "PINHOLE", "SIMPLE_RADIAL", "RADIAL", "OPENCV", "OPENCV_FISHEYE", "FULL_OPENCV", "FOV", "THIN_PRISM_FISHEYE"]
	
	for i in range(num_cameras):
		var cam = SparseCamera.new()
		var camera_id = file.get_32() # Read camera_id (uint32_t)
		var model_id = file.get_32() # Read model_id (int = int32)
		cam.model = camera_models[model_id] if model_id < camera_models.size() else "UNKNOWN"
		cam.width = file.get_64() # COLMAP uses uint64_t
		cam.height = file.get_64() # COLMAP uses uint64_t
		
		# Read parameters according to camera model
		# We must dynamically read parameters since models have different params count
		var num_params = 0
		match model_id:
			0: # SIMPLE_PINHOLE (f, cx, cy)
				num_params = 3
			1: # PINHOLE (fx, fy, cx, cy)
				num_params = 4
			2: # SIMPLE_RADIAL (f, cx, cy, k)
				num_params = 4
			3: # RADIAL (f, cx, cy, k1, k2)
				num_params = 5
			4: # OPENCV (fx, fy, cx, cy, k1, k2, p1, p2)
				num_params = 8
			5: # OPENCV_FISHEYE (fx, fy, cx, cy, k1, k2, k3, k4)
				num_params = 8
			6: # FULL_OPENCV (fx, fy, cx, cy, k1, k2, p1, p2, k3, k4, k5, k6)
				num_params = 12
			7: # FOV (fx, fy, cx, cy, omega)
				num_params = 5
			8: # THIN_PRISM_FISHEYE (fx, fy, cx, cy, k1, k2, p1, p2, k3, k4, sx1, sy1)
				num_params = 12
			_:
				num_params = 0
				push_warning("ColmapSparseImporter: Unknown camera model id: %d" % model_id)
		
		var params: Array[float] = []
		for p_idx in range(num_params):
			params.append(file.get_double())
			
		# Assign basic attributes if parameters were read
		if model_id == 0: # SIMPLE_PINHOLE
			cam.fx = params[0]
			cam.fy = params[0]
			cam.cx = params[1]
			cam.cy = params[2]
		elif model_id in [1, 2, 3, 4, 5, 6, 7, 8] and params.size() >= 4:
			cam.fx = params[0]
			if model_id == 2 or model_id == 3: # SIMPLE_RADIAL, RADIAL (f, cx, cy)
				cam.fy = params[0]
				cam.cx = params[1]
				cam.cy = params[2]
				if model_id == 3 and params.size() >= 5:
					cam.k1 = params[3]
					cam.k2 = params[4]
				else:
					cam.k1 = params[3]
			else: # PINHOLE, OPENCV, FULL_OPENCV etc (fx, fy, cx, cy)
				cam.fy = params[1]
				cam.cx = params[2]
				cam.cy = params[3]
				if num_params >= 6 and params.size() >= 6:
					cam.k1 = params[4]
					cam.k2 = params[5]
		
		cameras.append(cam)
	
	file.close()

func _images_file(path: String, images: Array[SparseImage]) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ColmapSparseImporter: images.bin not found")
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var num_images = file.get_64() # COLMAP uses uint64_t
	
	for i in range(num_images):
		var img = SparseImage.new()
		var image_id = file.get_32() # Read image_id (uint32_t)
		
		var qw = file.get_double()
		var qx = file.get_double()
		var qy = file.get_double()
		var qz = file.get_double()
		img.rotation = Basis(Quaternion(qx, qy, qz, qw))
		
		var tx = file.get_double()
		var ty = file.get_double()
		var tz = file.get_double()
		img.translation = Vector3(tx, ty, tz)
		
		img.camera_id = file.get_32()
		
		# Read null-terminated string for filename
		var filename = ""
		var c = file.get_8()
		while c != 0 and not file.eof_reached():
			filename += char(c)
			c = file.get_8()
		img.filename = filename
		
		# Read 2D points: num_points2D (uint64_t)
		var num_points2D = file.get_64()
		# We must skip or read the 2D points to advance the file pointer correctly!
		# Each 2D point consists of x (double), y (double), and point3D_id (uint64_t).
		# Total size per point = 8 + 8 + 8 = 24 bytes.
		var points2D_byte_size = num_points2D * 24
		file.seek(file.get_position() + points2D_byte_size)
		
		images.append(img)
	
	file.close()

func _points_file(path: String, points: Array[SparsePoint]) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ColmapSparseImporter: points3D.bin not found")
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var num_points = file.get_64() # uint64_t
	
	for i in range(num_points):
		var pt = SparsePoint.new()
		var point3D_id = file.get_64() # Read point3D_id (uint64_t)
		
		var x = file.get_double()
		var y = file.get_double()
		var z = file.get_double()
		pt.position = Vector3(x, y, z)
		
		# Read color (3 * uint8)
		var r = float(file.get_8()) / 255.0
		var g = float(file.get_8()) / 255.0
		var b = float(file.get_8()) / 255.0
		pt.color = Color(r, g, b)
		
		pt.error = file.get_double() # error (double) is BEFORE the track
		
		var track_len = file.get_64() # track_len (uint64_t)
		
		# Skip or read track: each track element has image_id (uint32_t) and point2D_idx (uint32_t).
		# Total size per track element = 8 bytes.
		var track_byte_size = track_len * 8
		file.seek(file.get_position() + track_byte_size)
		
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
		# COLMAP: camera_center = -R^T * t. Compute as Vector negation, not Basis unary minus.
		var rt: Vector3 = img.rotation.inverse() * img.translation
		positions.append(-rt)
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