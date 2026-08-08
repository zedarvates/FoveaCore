class_name FoveaDVLTExporter
extends RefCounted

## FoveaEngine — DVLT Camera Export (items 284-291)
## Exports camera poses in COLMAP format for external 3DGS training.

func export_colmap(poses: Array[Transform3D], intrinsics: Dictionary, output_dir: String) -> bool:
	"""Export camera poses as COLMAP cameras.txt + images.txt."""
	var absolute_output_dir: String = ProjectSettings.globalize_path(output_dir)
	if not DirAccess.dir_exists_absolute(absolute_output_dir):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_output_dir)
		if mkdir_error != OK:
			push_error("FoveaDVLTExporter: Cannot create output directory: %s" % output_dir)
			return false
	
	# cameras.txt
	var cam_file: FileAccess = FileAccess.open(output_dir.path_join("cameras.txt"), FileAccess.WRITE)
	if cam_file == null:
		push_error("FoveaDVLTExporter: Cannot write cameras.txt in %s" % output_dir)
		return false
	cam_file.store_line("# Camera list with one line of data per camera:")
	cam_file.store_line("# CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]")
	cam_file.store_line("1 PINHOLE %d %d %f %f %f %f" % [
		intrinsics.get("w", 1920), intrinsics.get("h", 1080),
		intrinsics.get("fx", 1000), intrinsics.get("fy", 1000),
		intrinsics.get("cx", 960), intrinsics.get("cy", 540)])
	cam_file.close()
	
	# images.txt
	var img_file: FileAccess = FileAccess.open(output_dir.path_join("images.txt"), FileAccess.WRITE)
	if img_file == null:
		push_error("FoveaDVLTExporter: Cannot write images.txt in %s" % output_dir)
		return false
	img_file.store_line("# Image list with two lines of data per image:")
	for i: int in range(poses.size()):
		var pose: Transform3D = poses[i]
		var q: Quaternion = pose.basis.get_rotation_quaternion()
		var t: Vector3 = pose.origin
		img_file.store_line("%d %.9f %.9f %.9f %.9f %.9f %.9f %.9f %d %s" % [
			i + 1, q.w, q.x, q.y, q.z, t.x, t.y, t.z, 1, "image_%04d.png" % i
		])
		img_file.store_line("")
	img_file.close()
	
	print("Exported %d poses to %s" % [poses.size(), output_dir])
	return true
