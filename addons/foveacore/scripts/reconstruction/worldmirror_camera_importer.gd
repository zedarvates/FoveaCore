extends Node
class_name WorldMirrorCameraImporter

## WorldMirrorCameraImporter — Parses WorldMirror 2.0 camera_params.json
## Converts OpenCV c2w extrinsics + intrinsics to Godot Camera3D nodes.
## Convention: OpenCV (X=right, Y=down, Z=forward) → Godot (X=right, Y=up, Z=backward)

signal cameras_imported(cameras: Array[Camera3D], count: int)
signal import_failed(reason: String)


class CameraInfo:
	var camera_id: int
	var c2w_godot: Transform3D
	var width: int
	var height: int
	var fx: float
	var fy: float
	var cx: float
	var cy: float
	var filename: String


func import_from_json(json_path: String) -> Array[CameraInfo]:
	var abs_path: String = ProjectSettings.globalize_path(json_path)
	if not FileAccess.file_exists(abs_path):
		import_failed.emit("camera_params.json not found: " + json_path)
		return []

	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		import_failed.emit("Cannot open: " + json_path)
		return []

	var content: String = file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(content)
	if data == null or not (data is Dictionary):
		import_failed.emit("Invalid JSON in camera params file")
		return []

	var result: Array[CameraInfo] = []

	var extrinsics: Array = data.get("extrinsics", []) as Array
	var intrinsics: Array = data.get("intrinsics", []) as Array
	var _num_cameras: int = data.get("num_cameras", 0) as int

	if extrinsics.is_empty() and intrinsics.is_empty():
		import_failed.emit("No camera data in JSON")
		return result

	for i: int in range(max(extrinsics.size(), intrinsics.size())):
		var info: CameraInfo = CameraInfo.new()
		info.camera_id = i

		if i < extrinsics.size():
			var ext: Dictionary = extrinsics[i] as Dictionary
			info.camera_id = ext.get("camera_id", i) as int
			var matrix: Array = ext.get("matrix", []) as Array
			if not matrix.is_empty():
				info.c2w_godot = _opencv_to_godot_c2w(matrix)

		if i < intrinsics.size():
			var intr: Dictionary = intrinsics[i] as Dictionary
			info.camera_id = intr.get("camera_id", i) as int
			var kmatrix: Array = intr.get("matrix", []) as Array
			if kmatrix.size() >= 3:
				info.fx = float(_safe_get(kmatrix[0] as Array, 0, 525.0))
				info.fy = float(_safe_get(kmatrix[1] as Array, 1, 525.0))
				info.cx = float(_safe_get(kmatrix[0] as Array, 2, 320.0))
				info.cy = float(_safe_get(kmatrix[1] as Array, 2, 240.0))

		result.append(info)

	print("WorldMirrorCameraImporter: Imported %d cameras" % result.size())
	return result


func create_godot_cameras(infos: Array[CameraInfo], scene_root: Node = null) -> Array[Camera3D]:
	var cameras: Array[Camera3D] = []
	var parent: Node = scene_root if scene_root else (Engine.get_main_loop() as SceneTree).root

	for info: CameraInfo in infos:
		var cam: Camera3D = Camera3D.new()
		cam.name = "WM2_Camera_%d" % info.camera_id
		cam.transform = info.c2w_godot
		cam.current = (info.camera_id == 0)
		parent.add_child(cam)
		cameras.append(cam)

	cameras_imported.emit(cameras, cameras.size())
	return cameras


func create_trajectory_curve(infos: Array[CameraInfo]) -> Path3D:
	"""Creates a Path3D from camera positions for fly-through visualization."""
	var path: Path3D = Path3D.new()
	path.name = "WM2_Trajectory"
	var curve: Curve3D = Curve3D.new()

	for info: CameraInfo in infos:
		curve.add_point(info.c2w_godot.origin)

	path.curve = curve
	return path


static func _opencv_to_godot_c2w(c2w_cv: Array) -> Transform3D:
	"""Convert OpenCV c2w 4x4 to Godot Transform3D.
	OpenCV: X=right, Y=down, Z=forward
	Godot:  X=right, Y=up, Z=backward
	Conversion: c2w_godot = c2w_cv * diag(1, -1, -1, 1)
	"""
	if c2w_cv.size() < 4:
		return Transform3D.IDENTITY

	var m: _Matrix4 = _Matrix4.new(c2w_cv)

	# Basis() consumes axis columns. Post-multiplying the OpenCV c2w by
	# diag(1, -1, -1) flips only the camera-local Y/Z axes. The camera and the
	# imported splats already share world coordinates, so translation is not
	# reflected.
	var basis: Basis = Basis(
		Vector3(m.m00, m.m10, m.m20),
		Vector3(-m.m01, -m.m11, -m.m21),
		Vector3(-m.m02, -m.m12, -m.m22),
	)
	var trans: Vector3 = Vector3(m.m03, m.m13, m.m23)

	return Transform3D(basis, trans)


static func _safe_get(arr: Array, column_idx: int, default_val: float = 0.0) -> float:
	if arr.size() < 3:
		return default_val
	var row: Variant = arr[column_idx] if column_idx < arr.size() else arr[0]
	if typeof(row) == TYPE_ARRAY:
		var row_arr: Array = row as Array
		return float(row_arr[2]) if row_arr.size() > 2 else default_val
	return default_val


# Lightweight 4x4 matrix helper (no dependencies)
class _Matrix4:
	var m00: float; var m01: float; var m02: float; var m03: float
	var m10: float; var m11: float; var m12: float; var m13: float
	var m20: float; var m21: float; var m22: float; var m23: float
	var m30: float; var m31: float; var m32: float; var m33: float

	func _init(arr: Array) -> void:
		if arr.size() < 4:
			return
		var r0: Array = arr[0] as Array; var r1: Array = arr[1] as Array; var r2: Array = arr[2] as Array; var r3: Array = arr[3] as Array
		m00 = r0[0] as float; m01 = r0[1] as float; m02 = r0[2] as float; m03 = r0[3] as float
		m10 = r1[0] as float; m11 = r1[1] as float; m12 = r1[2] as float; m13 = r1[3] as float
		m20 = r2[0] as float; m21 = r2[1] as float; m22 = r2[2] as float; m23 = r2[3] as float
		m30 = r3[0] as float; m31 = r3[1] as float; m32 = r3[2] as float; m33 = r3[3] as float
