extends Node
class_name DatasetExporter

## DatasetExporter — Prepares the workspace for COLMAP and 3DGS reconstruction
## Creates the standard directory structure:
## /session/
##   /input/ (original frames)
##   /masks/ (transparency masks)
##   /distorted/ (placeholder for undistortion)
##   /sparse/ (placeholder for SfM)

func prepare_workspace(session: ReconstructionSession) -> bool:
	var base_dir: String = session.output_directory
	var dir := DirAccess.open("res://")
	
	# Ensure relative path is converted to absolute for external tools
	var absolute_path: String = ProjectSettings.globalize_path(base_dir)
	
	if not DirAccess.dir_exists_absolute(absolute_path):
		var err = DirAccess.make_dir_recursive_absolute(absolute_path)
		if err != OK:
			push_error("DatasetExporter: Failed to create directory: ", absolute_path)
			return false

	var subdirs = ["images", "input", "masks", "stereo", "output"]
	for subdir in subdirs:
		var sub_path = absolute_path.path_join(subdir)
		if not DirAccess.dir_exists_absolute(sub_path):
			DirAccess.make_dir_recursive_absolute(sub_path)
			
	# Create .gdignore in the session workspace to prevent Godot from importing assets
	var gdignore_path = absolute_path.path_join(".gdignore")
	if not FileAccess.file_exists(gdignore_path):
		var f = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if f:
			f.close()
			print("DatasetExporter: Created .gdignore at ", gdignore_path)
			
	print("DatasetExporter: Workspace prepared at ", absolute_path)
	return true

## Find the trained .ply and copy it to a clean location in /output
func finalize_session(session: ReconstructionSession) -> void:
	var base_dir: String = ProjectSettings.globalize_path(session.output_directory)
	var trained_path = base_dir.path_join("output/point_cloud/iteration_7000/point_cloud.ply")
	var final_destination = base_dir.path_join("output").path_join(session.session_name + ".ply")
	
	if FileAccess.file_exists(trained_path):
		var err = DirAccess.copy_absolute(trained_path, final_destination)
		if err == OK:
			print("DatasetExporter: Final result ready at ", final_destination)
			session.splat_data_path = final_destination
		else:
			push_warning("DatasetExporter: Failed to copy final result.")
	else:
		# Search for any .ply in the output subfolders
		_find_and_copy_any_ply(base_dir.path_join("output"), final_destination, session)

func _find_and_copy_any_ply(search_dir: String, dest: String, session: ReconstructionSession) -> void:
	var dir = DirAccess.open(search_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_find_and_copy_any_ply(search_dir.path_join(file_name), dest, session)
			elif file_name.ends_with(".ply"):
				DirAccess.copy_absolute(search_dir.path_join(file_name), dest)
				session.splat_data_path = dest
				return
			file_name = dir.get_next()

func export_frame(session: ReconstructionSession, index: int, image: Image, mask: Image = null) -> void:
	var base_dir: String = ProjectSettings.globalize_path(session.output_directory)
	var frame_name: String = "frame_%04d.png" % index
	
	# Save input frame to both input and images directories for compatibility
	var input_path = base_dir.path_join("input").path_join(frame_name)
	image.save_png(input_path)
	
	var images_path = base_dir.path_join("images").path_join(frame_name)
	image.save_png(images_path)
	
	# Save mask if provided
	if mask:
		var mask_path = base_dir.path_join("masks").path_join(frame_name)
		mask.save_png(mask_path)

func create_metadata_json(session: ReconstructionSession) -> void:
	var base_dir: String = ProjectSettings.globalize_path(session.output_directory)
	var data = {
		"session_name": session.session_name,
		"video_path": session.video_path,
		"frame_count": session.frame_count,
		"extraction_fps": session.extraction_fps,
		"timestamp": Time.get_datetime_string_from_system()
	}
	
	var file = FileAccess.open(base_dir.path_join("metadata.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

## Verifies that the reconstruction folder contains all expected outputs (images, masks, database.db, sparse files)
func verify_reconstruction_outputs(session: ReconstructionSession) -> bool:
	var base_dir: String = ProjectSettings.globalize_path(session.output_directory)
	var ok := true
	
	# 1. Check input frames directory
	var input_dir = base_dir.path_join("input")
	if not DirAccess.dir_exists_absolute(input_dir):
		push_error("DatasetExporter: input directory is missing.")
		ok = false
	else:
		var dir = DirAccess.open(input_dir)
		dir.list_dir_begin()
		var file_count = 0
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".png"):
				file_count += 1
			file_name = dir.get_next()
		if file_count == 0:
			push_error("DatasetExporter: No frames found in input directory.")
			ok = false
			
	# 2. Check masks directory
	var masks_dir = base_dir.path_join("masks")
	if DirAccess.dir_exists_absolute(masks_dir):
		var dir = DirAccess.open(masks_dir)
		dir.list_dir_begin()
		var mask_count = 0
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".png"):
				mask_count += 1
			file_name = dir.get_next()
		print("DatasetExporter: Found %d masks." % mask_count)
	
	# If running WorldMirror 2.0, SfM outputs like database.db and sparse files are not generated
	if session.use_worldmirror:
		var ply_path = base_dir.path_join("gaussians.ply")
		if not FileAccess.file_exists(ply_path):
			push_error("DatasetExporter: gaussians.ply is missing from WorldMirror 2.0 output.")
			ok = false
		return ok
		
	# 3. Check database.db (only for COLMAP path)
	var db_path = base_dir.path_join("database.db")
	if not FileAccess.file_exists(db_path):
		push_error("DatasetExporter: database.db is missing.")
		ok = false
		
	# 4. Check sparse files (can be .bin or .txt)
	var sparse_0_dir = base_dir.path_join("sparse/0")
	if not DirAccess.dir_exists_absolute(sparse_0_dir):
		push_error("DatasetExporter: sparse/0 directory is missing.")
		ok = false
	else:
		var has_cameras = FileAccess.file_exists(sparse_0_dir.path_join("cameras.bin")) or FileAccess.file_exists(sparse_0_dir.path_join("cameras.txt"))
		var has_images = FileAccess.file_exists(sparse_0_dir.path_join("images.bin")) or FileAccess.file_exists(sparse_0_dir.path_join("images.txt"))
		var has_points = FileAccess.file_exists(sparse_0_dir.path_join("points3D.bin")) or FileAccess.file_exists(sparse_0_dir.path_join("points3D.txt"))
		
		if not has_cameras:
			push_error("DatasetExporter: cameras file is missing from sparse/0.")
			ok = false
		if not has_images:
			push_error("DatasetExporter: images file is missing from sparse/0.")
			ok = false
		if not has_points:
			push_error("DatasetExporter: points3D file is missing from sparse/0.")
			ok = false
			
	return ok
