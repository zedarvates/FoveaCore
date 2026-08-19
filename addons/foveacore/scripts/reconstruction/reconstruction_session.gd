extends Resource
class_name ReconstructionSession

## ReconstructionSession — Metadata and state for a StudioTo3D session

@export var session_name: String = "new_session"
@export var video_path: String = ""
@export var output_directory: String = "res://reconstructions/"

@export_group("Pre-processing")
@export var extraction_fps: int = 4
@export var background_threshold: float = 0.95
@export var blur_threshold: float = 0.25
@export var mask_mode: String = "Smart Studio"
@export var roi_rect: Rect2i = Rect2i(0, 0, 0, 0) # (0,0,0,0) means full image
@export var use_fast_sync: bool = false # Enable InSpatio-World STAR monocular path (legacy)
@export var use_worldmirror: bool = false # Enable WorldMirror 2.0 feed-forward reconstruction
@export var use_triposplat: bool = false # Enable TripoSplat single-image feed-forward reconstruction
@export var target_size: int = 952 # Max inference resolution for WorldMirror 2.0
@export var use_artifixer: bool = false # Enable ArtiFixer splat refinement
@export var artifixer_checkpoint: String = "" # Path to artifixer checkpoint PT file
@export var dry_run: bool = false
@export var exhaustive_matching: bool = false # Use COLMAP exhaustive matching instead of sequential (video) mode
@export_range(1000, 100000, 1000) var training_iterations: int = 30000

@export_group("Styling & Optimization")
@export var visual_style: String = "Photorealistic"
@export var splat_shape: String = "Triangle"
@export var splat_count_density: float = 1.0
@export var auto_tag_color: bool = false
@export var enable_wind: bool = false
@export var wind_speed: float = 0.0
@export var wind_strength: float = 0.0

@export_group("Reconstruction State")
@export var is_processed: bool = false
@export var frame_count: int = 0
@export var reconstruction_progress: float = 0.0
@export var status: String = "Idle"

@export_group("Results")
@export var low_poly_mesh_path: String = ""
@export var splat_data_path: String = ""
@export var preview_image: Texture2D = null

func _init(p_name: String = "new_session") -> void:
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
		"use_triposplat": use_triposplat,
		"target_size": target_size,
		"use_artifixer": use_artifixer,
		"artifixer_checkpoint": artifixer_checkpoint,
		"dry_run": dry_run,
		"exhaustive_matching": exhaustive_matching,
		"training_iterations": training_iterations,
		"visual_style": visual_style,
		"splat_shape": splat_shape,
		"splat_count_density": splat_count_density,
		"auto_tag_color": auto_tag_color,
		"enable_wind": enable_wind,
		"wind_speed": wind_speed,
		"wind_strength": wind_strength,
		"is_processed": is_processed,
		"frame_count": frame_count,
		"reconstruction_progress": reconstruction_progress,
		"status": status,
		"low_poly_mesh_path": low_poly_mesh_path,
		"splat_data_path": splat_data_path
	}

func from_dict(dict: Dictionary) -> void:
	session_name = dict.get("session_name", session_name) as String
	video_path = dict.get("video_path", video_path) as String
	output_directory = dict.get("output_directory", output_directory) as String
	extraction_fps = dict.get("extraction_fps", extraction_fps) as int
	background_threshold = dict.get("background_threshold", background_threshold) as float
	blur_threshold = dict.get("blur_threshold", blur_threshold) as float
	mask_mode = dict.get("mask_mode", mask_mode) as String
	if dict.has("roi_rect"):
		var r: Variant = dict["roi_rect"]
		if r is Array and r.size() == 4:
			roi_rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	use_fast_sync = dict.get("use_fast_sync", use_fast_sync) as bool
	use_worldmirror = dict.get("use_worldmirror", use_worldmirror) as bool
	use_triposplat = dict.get("use_triposplat", use_triposplat) as bool
	target_size = dict.get("target_size", target_size) as int
	use_artifixer = dict.get("use_artifixer", use_artifixer) as bool
	artifixer_checkpoint = dict.get("artifixer_checkpoint", artifixer_checkpoint) as String
	dry_run = dict.get("dry_run", dry_run) as bool
	exhaustive_matching = dict.get("exhaustive_matching", exhaustive_matching) as bool
	# Sessions saved before the quality field existed were trained at 7k.
	training_iterations = dict.get("training_iterations", 7000) as int
	var loaded_visual_style: String = dict.get("visual_style", visual_style) as String
	# Migrate sessions saved before the preset was named explicitly.
	visual_style = "Photorealistic" if loaded_visual_style == "Realistic" else loaded_visual_style
	splat_shape = dict.get("splat_shape", splat_shape) as String
	splat_count_density = dict.get("splat_count_density", splat_count_density) as float
	auto_tag_color = dict.get("auto_tag_color", auto_tag_color) as bool
	enable_wind = dict.get("enable_wind", enable_wind) as bool
	wind_speed = dict.get("wind_speed", wind_speed) as float
	wind_strength = dict.get("wind_strength", wind_strength) as float
	is_processed = dict.get("is_processed", is_processed) as bool
	frame_count = dict.get("frame_count", frame_count) as int
	reconstruction_progress = dict.get("reconstruction_progress", reconstruction_progress) as float
	status = dict.get("status", status) as String
	low_poly_mesh_path = dict.get("low_poly_mesh_path", low_poly_mesh_path) as String
	splat_data_path = dict.get("splat_data_path", splat_data_path) as String


func get_training_point_cloud_path() -> String:
	return output_directory.path_join(
		"output/point_cloud/iteration_%d/point_cloud.ply" % training_iterations
	)
