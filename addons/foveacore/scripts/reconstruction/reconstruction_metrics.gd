extends Resource
class_name ReconstructionMetrics

## ReconstructionMetrics — Dataset quality tracking for StudioTo3D
## Helps identifying bad frames before starting the expensive pipeline

@export var average_blur: float = 0.0
@export var background_coverage: float = 0.0
@export var coverage_map: Array[Vector3] = [] # Camera positions
@export var bad_frames_indices: Array[int] = []

func add_frame_metrics(index: int, blur_score: float, mask_coverage: float) -> void:
	average_blur = (average_blur + blur_score) / 2.0
	background_coverage = (background_coverage + mask_coverage) / 2.0
	
	# Simple quality threshold
	if blur_score < 0.2 or mask_coverage < 0.1:
		bad_frames_indices.append(index)

func get_quality_report() -> String:
	var report = "Dataset Quality Report:\n"
	report += "- Average Blur: %.2f (lower is more blur)\n" % average_blur
	report += "- Mask Coverage: %.2f (objects detected in frames)\n" % background_coverage
	report += "- Bad frames detected: %d\n" % bad_frames_indices.size()
	
	if bad_frames_indices.size() > 0:
		report += "- Consider re-shooting or increasing threshold."
	
	return report
