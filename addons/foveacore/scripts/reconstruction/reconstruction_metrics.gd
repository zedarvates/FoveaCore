extends Resource
class_name ReconstructionMetrics

## ReconstructionMetrics — Dataset quality tracking for StudioTo3D
## Helps identifying bad frames before starting the expensive pipeline

signal quality_warning(message: String)
signal quality_score_updated(score: float)

@export var average_blur: float = 0.0
@export var background_coverage: float = 0.0
@export var coverage_map: Array[Vector3] = []
@export var bad_frames_indices: Array[int] = []

@export var frame_count: int = 0
@export var total_processing_time_ms: float = 0.0
@export var brightness_score: float = 0.0
@export var color_variance: float = 0.0
@export var depth_confidence: float = 0.0
@export var splat_density: float = 0.0
@export var reconstruction_quality_score: float = 0.0

var _frame_metrics: Array[Dictionary] = []

func add_frame_metrics(index: int, blur_score: float, mask_coverage: float, brightness: float = 0.0, variance: float = 0.0) -> void:
	frame_count += 1
	
	average_blur = (average_blur * (frame_count - 1) + blur_score) / frame_count
	background_coverage = (background_coverage * (frame_count - 1) + mask_coverage) / frame_count
	brightness_score = (brightness_score * (frame_count - 1) + brightness) / frame_count
	color_variance = (color_variance * (frame_count - 1) + variance) / frame_count
	
	_frame_metrics.append({
		"index": index,
		"blur": blur_score,
		"coverage": mask_coverage,
		"brightness": brightness,
		"variance": variance,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	if blur_score < 0.2 or mask_coverage < 0.1:
		bad_frames_indices.append(index)
		quality_warning.emit("Frame %d has low quality (blur: %.2f, coverage: %.2f)" % [index, blur_score, mask_coverage])

	reconstruction_quality_score = _calculate_quality_score()

func add_depth_metrics(depth_confidence_value: float) -> void:
	depth_confidence = depth_confidence_value
	reconstruction_quality_score = _calculate_quality_score()

func add_color_metrics(brightness: float, variance: float) -> void:
	brightness_score = brightness
	color_variance = variance
	reconstruction_quality_score = _calculate_quality_score()

func add_splat_metrics(density: float, count: int) -> void:
	splat_density = density
	
	var _good_splats: float = float(count) * density
	reconstruction_quality_score = _calculate_quality_score()

func _calculate_quality_score() -> float:
	if frame_count == 0:
		return 0.0
	
	var score: float = 0.0
	
	score += background_coverage * 40.0
	
	if average_blur > 0.5:
		score += 20.0
	elif average_blur > 0.3:
		score += 10.0
	
	if brightness_score > 0.3 and brightness_score < 0.9:
		score += 15.0
	
	if color_variance > 0.1:
		score += 15.0
	
	if depth_confidence > 0.7:
		score += 10.0
	
	var bad_ratio: float = float(bad_frames_indices.size()) / float(frame_count)
	score -= bad_ratio * 20.0
	
	quality_score_updated.emit(score)
	return clampf(score, 0.0, 100.0)

func get_quality_grade() -> String:
	var score: float = reconstruction_quality_score
	if score >= 80.0:
		return "A (Excellent)"
	elif score >= 60.0:
		return "B (Good)"
	elif score >= 40.0:
		return "C (Fair)"
	elif score >= 20.0:
		return "D (Poor)"
	else:
		return "F (Failed)"

func get_worst_frames(count: int = 5) -> Array[int]:
	var sorted: Array = _frame_metrics.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["blur"] as float) < (b["blur"] as float) or (a["coverage"] as float) < (b["coverage"] as float))
	var result: Array[int] = []
	for i: int in range(min(count, sorted.size())):
		result.append(sorted[i]["index"] as int)
	return result

func get_quality_report() -> String:
	var report: String = "=== Reconstruction Quality Report ===\n"
	report += "Grade: %s\n\n" % get_quality_grade()
	report += "Overall Score: %.1f/100\n\n" % reconstruction_quality_score
	report += "Frame Analysis:\n"
	report += "- Total Frames: %d\n" % frame_count
	report += "- Bad Frames: %d (%.1f%%)\n\n" % [bad_frames_indices.size(), float(bad_frames_indices.size()) / max(frame_count, 1) * 100.0]
	report += "Visual Quality:\n"
	report += "- Average Blur: %.2f\n" % average_blur
	report += "- Mask Coverage: %.2f%%\n" % (background_coverage * 100.0)
	report += "- Brightness: %.2f\n" % brightness_score
	report += "- Color Variance: %.2f\n\n" % color_variance
	report += "3D Reconstruction:\n"
	report += "- Depth Confidence: %.2f\n" % depth_confidence
	report += "- Splat Density: %.2f\n\n" % splat_density
	
	if not bad_frames_indices.is_empty():
		report += "Worst Frames: %s\n" % str(get_worst_frames(5))
		report += "- Consider removing or re-shooting these frames.\n"
	
	report += "================================="
	return report

func export_to_dict() -> Dictionary:
	return {
		"grade": get_quality_grade(),
		"score": reconstruction_quality_score,
		"frame_count": frame_count,
		"bad_frames_count": bad_frames_indices.size(),
		"average_blur": average_blur,
		"background_coverage": background_coverage,
		"brightness_score": brightness_score,
		"color_variance": color_variance,
		"depth_confidence": depth_confidence,
		"splat_density": splat_density,
		"worst_frames": get_worst_frames(5),
		"timestamp": Time.get_unix_time_from_system()
	}
