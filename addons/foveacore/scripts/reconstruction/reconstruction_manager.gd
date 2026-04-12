extends Node
class_name ReconstructionManager

## ReconstructionManager — Coordinates reconstruction sessions
## Interaces with externally compiled tools for SfM and 3DGS-Training

signal session_started(name: String)
signal session_progress_updated(progress: float)
signal session_completed(result: Resource)

@export var processor: StudioProcessor = null
@export var exporter: DatasetExporter = null
@export var backend: ReconstructionBackend = null
@export var metrics: ReconstructionMetrics = null
@export var default_output_dir: String = "res://reconstructions/"

var active_sessions: Dictionary = {}

func _ready() -> void:
	if processor == null:
		processor = StudioProcessor.new()
		add_child(processor)
	
	if exporter == null:
		exporter = DatasetExporter.new()
		add_child(exporter)
	
	if backend == null:
		backend = ReconstructionBackend.new()
		add_child(backend)
		backend.command_started.connect(_on_backend_started)
		backend.command_finished.connect(_on_backend_finished)

## Start a reconstruction session
func create_new_session(video_path: String, name: String = "") -> ReconstructionSession:
	var sess_name: String = name if not name.is_empty() else "sess_" + str(Time.get_unix_time_from_system())
	var session: ReconstructionSession = ReconstructionSession.new(sess_name)
	session.video_path = video_path
	session.output_directory = default_output_dir + sess_name
	
	active_sessions[sess_name] = session
	return session

## Step 1: Extraction & Masking
func run_extraction(session: ReconstructionSession, mask_mode: String = "Studio White") -> void:
	session_started.emit(session.session_name)
	session.status = "Pre-processing"
	
	# Prepare metrics
	metrics = ReconstructionMetrics.new()
	
	# Prepare workspace
	exporter.prepare_workspace(session)
	
	# Extract frames
	processor.frame_extracted.connect(func(idx, img): 
		var mask = processor.mask_background(img, mask_mode, session.background_threshold, session.roi_rect)
		exporter.export_frame(session, idx, img, mask)
		
		# Calculate mask coverage metrics
		var coverage = _calculate_mask_coverage(mask)
		metrics.add_frame_metrics(idx, 1.0, coverage)
	)
	
	await processor.extract_frames(session)
	exporter.create_metadata_json(session)
	
	session.status = "Pre-processed"
	print(metrics.get_quality_report())
	session_progress_updated.emit(100.0)

func _calculate_mask_coverage(mask: Image) -> float:
	# Estimate surface covered by non-transparent pixels
	var transparent_pixels = 0
	var size = mask.get_size()
	# Sample every 10th pixel for performance
	for y in range(0, size.y, 10):
		for x in range(0, size.x, 10):
			if mask.get_pixel(x, y).a < 0.1:
				transparent_pixels += 1
	
	var total_sampled = (size.x/10) * (size.y/10)
	return 1.0 - (float(transparent_pixels) / float(total_sampled))

## Step 2: SfM (COLMAP)
func run_sfm(session: ReconstructionSession) -> void:
	session.status = "SfM Running"
	backend.execute_reconstruction(session)

## Step 3: Training (3DGS)
func run_training(session: ReconstructionSession) -> void:
	session.is_processed = true # Toggle for backend to run training instead of SfM
	backend.execute_reconstruction(session)

func _on_backend_started(task: String) -> void:
	print("Manager: Backend started -> ", task)

func _on_backend_finished(status: int, output: String) -> void:
	print("Manager: Backend finished -> ", output)
	# Update manager state here if needed
