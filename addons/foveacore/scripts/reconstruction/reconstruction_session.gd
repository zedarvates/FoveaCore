extends Resource
class_name ReconstructionSession

## ReconstructionSession — Metadata and state for a StudioTo3D session

@export var session_name: String = "new_session"
@export var video_path: String = ""
@export var output_directory: String = "res://reconstructions/"

@export_group("Pre-processing")
@export var extraction_fps: int = 2
@export var background_threshold: float = 0.95
@export var blur_threshold: float = 0.25
@export var mask_mode: String = "Smart Studio"
@export var roi_rect: Rect2i = Rect2i(0, 0, 0, 0) # (0,0,0,0) means full image
@export var use_fast_sync: bool = false # Enable InSpatio-World STAR monocular path (legacy)
@export var use_worldmirror: bool = false # Enable WorldMirror 2.0 feed-forward reconstruction
@export var target_size: int = 952 # Max inference resolution for WorldMirror 2.0
@export var dry_run: bool = false
@export var exhaustive_matching: bool = false # Use COLMAP exhaustive matching instead of sequential (video) mode

@export_group("Reconstruction State")
@export var is_processed: bool = false
@export var frame_count: int = 0
@export var reconstruction_progress: float = 0.0
@export var status: String = "Idle"

@export_group("Results")
@export var low_poly_mesh_path: String = ""
@export var splat_data_path: String = ""
@export var preview_image: Texture2D = null

func _init(p_name: String = "new_session"):
	session_name = p_name

func to_dict() -> Dictionary:
	return {
		"session_name": session_name,
		"video_path": video_path,
		"output_directory": output_directory,
		"extraction_fps": extraction_fps,
		"background_threshold": background_threshold,
		"blur_threshold": blur_threshold,
		"mask_mode": mask_mode,
		"roi_rect": [roi_rect.position.x, roi_rect.position.y, roi_rect.size.x, roi_rect.size.y],
		"use_fast_sync": use_fast_sync,
		"use_worldmirror": use_worldmirror,
		"target_size": target_size,
		"dry_run": dry_run,
		"exhaustive_matching": exhaustive_matching,
		"is_processed": is_processed,
		"frame_count": frame_count,
		"reconstruction_progress": reconstruction_progress,
		"status": status,
		"low_poly_mesh_path": low_poly_mesh_path,
		"splat_data_path": splat_data_path
	}

func from_dict(dict: Dictionary) -> void:
	session_name = dict.get("session_name", session_name)
	video_path = dict.get("video_path", video_path)
	output_directory = dict.get("output_directory", output_directory)
	extraction_fps = dict.get("extraction_fps", extraction_fps)
	background_threshold = dict.get("background_threshold", background_threshold)
	blur_threshold = dict.get("blur_threshold", blur_threshold)
	mask_mode = dict.get("mask_mode", mask_mode)
	if dict.has("roi_rect"):
		var r = dict["roi_rect"]
		if r is Array and r.size() == 4:
			roi_rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	use_fast_sync = dict.get("use_fast_sync", use_fast_sync)
	use_worldmirror = dict.get("use_worldmirror", use_worldmirror)
	target_size = dict.get("target_size", target_size)
	dry_run = dict.get("dry_run", dry_run)
	exhaustive_matching = dict.get("exhaustive_matching", exhaustive_matching)
	is_processed = dict.get("is_processed", is_processed)
	frame_count = dict.get("frame_count", frame_count)
	reconstruction_progress = dict.get("reconstruction_progress", reconstruction_progress)
	status = dict.get("status", status)
	low_poly_mesh_path = dict.get("low_poly_mesh_path", low_poly_mesh_path)
	splat_data_path = dict.get("splat_data_path", splat_data_path)
