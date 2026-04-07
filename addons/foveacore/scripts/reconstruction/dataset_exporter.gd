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

    var subdirs = ["input", "masks", "sparse", "stereo", "sparse/0"]
    for subdir in subdirs:
        var sub_path = absolute_path.path_join(subdir)
        if not DirAccess.dir_exists_absolute(sub_path):
            DirAccess.make_dir_recursive_absolute(sub_path)
            
    print("DatasetExporter: Workspace prepared at ", absolute_path)
    return true

func export_frame(session: ReconstructionSession, index: int, image: Image, mask: Image = null) -> void:
    var base_dir: String = ProjectSettings.globalize_path(session.output_directory)
    var frame_name: String = "frame_%04d.png" % index
    
    # Save input frame
    var input_path = base_dir.path_join("input").path_join(frame_name)
    image.save_png(input_path)
    
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
