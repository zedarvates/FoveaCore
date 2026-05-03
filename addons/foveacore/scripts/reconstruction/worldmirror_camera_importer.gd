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
	var abs_path = ProjectSettings.globalize_path(json_path)
	if not FileAccess.file_exists(abs_path):
		import_failed.emit("camera_params.json not found: " + json_path)
		return []

	var file = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		import_failed.emit("Cannot open: " + json_path)
		return []

	var content = file.get_as_text()
	file.close()

	var data = JSON.parse_string(content)
	if data == null:
		import_failed.emit("Invalid JSON in camera params file")
		return []

	var result: Array[CameraInfo] = []

	var extrinsics = data.get("extrinsics", [])
	var intrinsics = data.get("intrinsics", [])
	var num_cameras = data.get("num_cameras", 0)

	if extrinsics.is_empty() and intrinsics.is_empty():
		import_failed.emit("No camera data in JSON")
		return result

	for i in range(max(extrinsics.size(), intrinsics.size())):
		var info = CameraInfo.new()
		info.camera_id = i

		if i < extrinsics.size():
			var ext = extrinsics[i]
			info.camera_id = ext.get("camera_id", i)
			var matrix = ext.get("matrix", [])
			if not matrix.is_empty():
				info.c2w_godot = _opencv_to_godot_c2w(matrix)

		if i < intrinsics.size():
			var intr = intrinsics[i]
			info.camera_id = intr.get("camera_id", i)
			var kmatrix = intr.get("matrix", [])
			if kmatrix.size() >= 3:
				info.fx = float(_safe_get(kmatrix[0], 0, 525.0))
				info.fy = float(_safe_get(kmatrix[1], 1, 525.0))
				info.cx = float(_safe_get(kmatrix[0], 2, 320.0))
				info.cy = float(_safe_get(kmatrix[1], 2, 240.0))

		result.append(info)

	print("WorldMirrorCameraImporter: Imported %d cameras" % result.size())
	return result


func create_godot_cameras(infos: Array[CameraInfo], scene_root: Node = null) -> Array[Camera3D]:
	var cameras: Array[Camera3D] = []
	var parent = scene_root if scene_root else Engine.get_main_loop().root

	for info in infos:
		var cam = Camera3D.new()
		cam.name = "WM2_Camera_%d" % info.camera_id
		cam.transform = info.c2w_godot
		cam.current = (info.camera_id == 0)
		parent.add_child(cam)
		cameras.append(cam)

	cameras_imported.emit(cameras, cameras.size())
	return cameras


func create_trajectory_curve(infos: Array[CameraInfo]) -> Path3D:
	"""Creates a Path3D from camera positions for fly-through visualization."""
	var path = Path3D.new()
	path.name = "WM2_Trajectory"
	var curve = Curve3D.new()

	for info in infos:
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

	var m := _Matrix4.new(c2w_cv)

	var basis := Basis(
		Vector3(m.m00, m.m01, m.m02),
		Vector3(m.m10, m.m11, m.m12),
		Vector3(m.m20, m.m21, m.m22),
	)

	# Post-multiply: basis * S where S = diag(1, -1, -1)
	var s_basis := Basis(
		Vector3(1, 0, 0),
		Vector3(0, -1, 0),
		Vector3(0, 0, -1),
	)
	basis = basis * s_basis

	# Translation: flip Y and Z
	var trans := Vector3(m.m03, -m.m13, -m.m23)

	return Transform3D(basis, trans)


static func _safe_get(arr, column_idx: int, default_val = 0) -> float:
	if arr.size() < 3:
		return default_val
	var row = arr[column_idx] if column_idx < arr.size() else arr[0]
	if typeof(row) == TYPE_ARRAY:
		return row[2] if row.size() > 2 else default_val
	return default_val


# Lightweight 4x4 matrix helper (no dependencies)
class _Matrix4:
	var m00: float; var m01: float; var m02: float; var m03: float
	var m10: float; var m11: float; var m12: float; var m13: float
	var m20: float; var m21: float; var m22: float; var m23: float
	var m30: float; var m31: float; var m32: float; var m33: float

	func _init(arr: Array):
		if arr.size() < 4:
			return
		var r0 = arr[0]; var r1 = arr[1]; var r2 = arr[2]; var r3 = arr[3]
		m00 = r0[0]; m01 = r0[1]; m02 = r0[2]; m03 = r0[3]
		m10 = r1[0]; m11 = r1[1]; m12 = r1[2]; m13 = r1[3]
		m20 = r2[0]; m21 = r2[1]; m22 = r2[2]; m23 = r2[3]
		m30 = r3[0]; m31 = r3[1]; m32 = r3[2]; m33 = r3[3]
