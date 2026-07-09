class_name FoveaDVLTExporter
extends RefCounted

## FoveaEngine — DVLT Camera Export (items 284-291)
## Exports camera poses in COLMAP format for external 3DGS training.

func export_colmap(poses: Array[Transform3D], intrinsics: Dictionary, output_dir: String) -> bool:
	"""Export camera poses as COLMAP cameras.txt + images.txt."""
	var dir = DirAccess.open(output_dir) if DirAccess.dir_exists(output_dir) else DirAccess.make_dir_recursive(output_dir)
	if not dir: return false
	
	# cameras.txt
	var cam_file = FileAccess.open(output_dir.path_join("cameras.txt"), FileAccess.WRITE)
	cam_file.store_line("# Camera list with one line of data per camera:")
	cam_file.store_line("# CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]")
	cam_file.store_line("1 PINHOLE %d %d %f %f %f %f" % [
		intrinsics.get("w", 1920), intrinsics.get("h", 1080),
		intrinsics.get("fx", 1000), intrinsics.get("fy", 1000),
		intrinsics.get("cx", 960), intrinsics.get("cy", 540)])
	cam_file.close()
	
	# images.txt
	var img_file = FileAccess.open(output_dir.path_join("images.txt"), FileAccess.WRITE)
	img_file.store_line("# Image list with two lines of data per image:")
	for i, pose in enumerate(poses):
		var q = pose.basis.get_rotation_quaternion()
		var t = pose.origin
		img_file.store_line("%d %s %s %s %f %f %f %d %s %s" % [i+1, "QW", "QX", "QY", q.w, q.x, q.y, q.z, t.x, t.y, t.z, 1, "image_%04d.png" % i])
		img_file.store_line("")
	img_file.close()
	
	print("Exported %d poses to %s" % [poses.size(), output_dir])
	return true
