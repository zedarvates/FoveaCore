extends Resource
class_name ReconstructionSession

## ReconstructionSession — Metadata and state for a StudioTo3D session

@export var session_name: String = "new_session"
@export var video_path: String = ""
@export var output_directory: String = "res://reconstructions/"

@export_group("Pre-processing")
@export var extraction_fps: int = 2
@export var background_threshold: float = 0.95
@export var blur_threshold: float = 0.5
@export var roi_rect: Rect2i = Rect2i(0, 0, 0, 0) # (0,0,0,0) means full image

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
