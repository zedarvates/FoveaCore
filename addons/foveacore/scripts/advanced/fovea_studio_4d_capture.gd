class_name FoveaStudio4DCapture
extends RefCounted

## Explicit availability boundary for the future 4D capture pipeline.
## A successful capture must only be reported after reconstruction, alignment,
## cleaning, and .fovea flipbook serialization are all implemented.

signal capture_progress(frame: int, total: int)
signal capture_complete(output_path: String)
signal capture_error(message: String)

@export var auto_align: bool = true
@export var auto_clean: bool = true
@export var auto_deduplicate: bool = true
@export_range(1, 120) var frame_stride: int = 1

func capture_sequence(_video_path: String, _output_dir: String, _num_frames: int = 24) -> void:
	var message: String = "4D capture is unavailable: per-frame reconstruction, alignment, cleaning, and flipbook serialization are not wired."
	push_error("FoveaStudio4DCapture: %s" % message)
	capture_error.emit(message)
