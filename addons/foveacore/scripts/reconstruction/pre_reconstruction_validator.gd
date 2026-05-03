extends Node
class_name PreReconstructionValidator

signal validation_started()
signal validation_progress(message: String, percent: float)
signal validation_completed(result: ValidationResult)
signal validation_failed(reason: String)

class ValidationResult:
	var is_valid: bool = true
	var issues: Array[String] = []
	var warnings: Array[String] = []
	var score: float = 100.0
	var suggestions: Array[String] = []
	
	func add_issue(msg: String) -> void:
		issues.append(msg)
		is_valid = false
		score -= 20.0
	
	func add_warning(msg: String) -> void:
		warnings.append(msg)
		score -= 5.0
	
	func add_suggestion(msg: String) -> void:
		suggestions.append(msg)

var _processor: StudioProcessor = null

func _ready() -> void:
	_processor = StudioProcessor.new()
	add_child(_processor)

func validate_video(video_path: String) -> ValidationResult:
	var result = ValidationResult.new()
	validation_started.emit()
	
	validation_progress.emit("Checking file existence...", 5)
	if not FileAccess.file_exists(video_path):
		result.add_issue("Video file does not exist")
		validation_failed.emit("File not found")
		validation_completed.emit(result)
		return result
	
	validation_progress.emit("Analyzing video properties...", 20)
	var video_info = _get_video_info(video_path)
	if video_info.is_empty():
		result.add_issue("Unable to read video file")
		validation_failed.emit("Cannot read video")
		validation_completed.emit(result)
		return result
	
	_resolution_check(video_info, result)
	_framerate_check(video_info, result)
	_duration_check(video_info, result)
	_codec_check(video_info, result)
	
	validation_progress.emit("Extracting sample frames...", 50)
	var sample_frames = _extract_sample_frames(video_path, 5)
	if sample_frames.is_empty():
		result.add_issue("Failed to extract frames from video")
		validation_failed.emit("Frame extraction failed")
		validation_completed.emit(result)
		return result
	
	validation_progress.emit("Analyzing lighting conditions...", 70)
	_analyze_lighting(sample_frames, result)
	
	validation_progress.emit("Checking background...", 85)
	_check_background_quality(sample_frames, result)
	
	result.score = clampf(result.score, 0.0, 100.0)
	
	validation_progress.emit("Validation complete", 100)
	validation_completed.emit(result)
	
	return result

func _get_video_info(path: String) -> Dictionary:
	var info = {}
	var args = [
		"-i", ProjectSettings.globalize_path(path),
		"-f", "null", "-"
	]
	var cmd = _processor.ffmpeg_path if not _processor.ffmpeg_path.is_empty() else "ffmpeg"
	var out = []
	OS.execute(cmd, args, out)
	
	var output = " ".join(out)
	
	var res_match = RegEx.new()
	res_match.compile("(\\d{2,5})x(\\d{2,5})")
	var match_result = res_match.search(output)
	if match_result:
		info["width"] = int(match_result.get_string(1))
		info["height"] = int(match_result.get_string(2))
	
	var fps_match = RegEx.new()
	fps_match.compile("(\\d+(?:\\.\\d+)?)\\s*fps")
	match_result = fps_match.search(output)
	if match_result:
		info["fps"] = float(match_result.get_string(1))
	
	var duration_match = RegEx.new()
	duration_match.compile("Duration:\\s*(\\d+):(\\d+):(\\d+)\\.")
	match_result = duration_match.search(output)
	if match_result:
		var h = int(match_result.get_string(1))
		var m = int(match_result.get_string(2))
		var s = int(match_result.get_string(3))
		info["duration_seconds"] = h * 3600 + m * 60 + s
	
	var codec_match = RegEx.new()
	codec_match.compile("Video:\\s*(\\w+)")
	match_result = codec_match.search(output)
	if match_result:
		info["codec"] = match_result.get_string(1)
	
	return info

func _resolution_check(info: Dictionary, result: ValidationResult) -> void:
	var width = info.get("width", 0)
	var height = info.get("height", 0)
	
	if width < 1280 or height < 720:
		result.add_issue("Resolution too low (minimum 1280x720 recommended). Current: %dx%d" % [width, height])
	elif width < 1920 or height < 1080:
		result.add_warning("Resolution below 1080p. Consider using higher resolution for better results.")
	else:
		result.add_suggestion("Resolution is good: %dx%d" % [width, height])

func _framerate_check(info: Dictionary, result: ValidationResult) -> void:
	var fps = info.get("fps", 0)
	
	if fps < 24:
		result.add_issue("Frame rate too low (minimum 24fps recommended). Current: %.1ffps" % fps)
	elif fps < 30:
		result.add_warning("Frame rate below 30fps. Consider using higher frame rate.")
	elif fps >= 60:
		result.add_suggestion("High frame rate detected (%.1ffps). This will produce better results." % fps)

func _duration_check(info: Dictionary, result: ValidationResult) -> void:
	var duration = info.get("duration_seconds", 0)
	
	if duration < 3:
		result.add_issue("Video too short (minimum 3 seconds recommended). Current: %ds" % duration)
	elif duration < 10:
		result.add_warning("Short video. Consider using longer video for better reconstruction.")
	elif duration > 120:
		result.add_warning("Long video. Processing will take longer. Consider trimming to 30-60s.")
	else:
		result.add_suggestion("Duration is optimal: %ds" % duration)

func _codec_check(info: Dictionary, result: ValidationResult) -> void:
	var codec = info.get("codec", "")
	var supported = ["h264", "hevc", "av1", "vp9", "mpeg4"]
	
	if codec.is_empty():
		result.add_warning("Unable to detect video codec")
	elif codec.to_lower() not in supported:
		result.add_warning("Uncommon codec: %s. May cause issues." % codec)

func _extract_sample_frames(path: String, count: int) -> Array[Image]:
	var frames: Array[Image] = []
	var temp_dir = OS.get_user_data_dir() + "/fovea_validate_temp"
	
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	DirAccess.make_dir_recursive_absolute(temp_dir)
	
	var duration = _get_video_info(path).get("duration_seconds", 10)
	var interval = max(duration / (count + 1), 1)
	
	for i in range(count):
		var timestamp = interval * (i + 1)
		var output_path = temp_dir + "/frame_%d.jpg" % i
		
		var args = [
			"-ss", str(timestamp),
			"-i", ProjectSettings.globalize_path(path),
			"-frames:v", "1",
			"-q:v", "2",
			ProjectSettings.globalize_path(output_path)
		]
		
		var cmd = _processor.ffmpeg_path if not _processor.ffmpeg_path.is_empty() else "ffmpeg"
		OS.execute(cmd, args, [])
		
		if FileAccess.file_exists(output_path):
			var img = Image.load_from_file(output_path)
			if img:
				frames.append(img)
	
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	
	return frames

func _analyze_lighting(frames: Array[Image], result: ValidationResult) -> void:
	var total_brightness = 0.0
	var sample_count = 0
	
	for frame in frames:
		for y in range(0, frame.get_height(), 20):
			for x in range(0, frame.get_width(), 20):
				var pixel = frame.get_pixel(x, y)
				var brightness = (pixel.r + pixel.g + pixel.b) / 3.0
				total_brightness += brightness
				sample_count += 1
	
	var avg_brightness = total_brightness / max(sample_count, 1)
	
	if avg_brightness < 0.2:
		result.add_issue("Video is too dark. Improve lighting conditions.")
	elif avg_brightness < 0.4:
		result.add_warning("Video is somewhat dark. Consider better lighting.")
	elif avg_brightness > 0.9:
		result.add_warning("Video may be overexposed. Check lighting.")
	else:
		result.add_suggestion("Lighting conditions are good (brightness: %.2f)" % avg_brightness)

func _check_background_quality(frames: Array[Image], result: ValidationResult) -> void:
	var studio_white_count = 0
	var chroma_green_count = 0
	
	for frame in frames:
		var bg_pixels = 0
		var white_bg = 0
		var green_bg = 0
		
		for y in range(frame.get_height()):
			for x in range(frame.get_width()):
				var pixel = frame.get_pixel(x, y)
				
				if pixel.r > 0.85 and pixel.g > 0.85 and pixel.b > 0.85:
					white_bg += 1
				elif pixel.g > pixel.r + 0.15 and pixel.g > pixel.b + 0.15:
					green_bg += 1
				
				bg_pixels += 1
		
		var white_ratio = float(white_bg) / float(bg_pixels)
		var green_ratio = float(green_bg) / float(bg_pixels)
		
		if white_ratio > 0.3:
			studio_white_count += 1
		if green_ratio > 0.3:
			chroma_green_count += 1
	
	var has_clean_bg = studio_white_count >= frames.size() / 2 or chroma_green_count >= frames.size() / 2
	
	if not has_clean_bg:
		result.add_warning("No consistent clean background detected. Consider using studio white or chroma key green.")

func get_report_text(result: ValidationResult) -> String:
	var report = "=== Pre-Reconstruction Validation ===\n\n"
	report += "Score: %.0f/100\n" % result.score
	report += "Status: %s\n\n" % ("PASS" if result.is_valid else "FAIL")
	
	if not result.issues.is_empty():
		report += "ISSUES:\n"
		for issue in result.issues:
			report += "  ❌ %s\n" % issue
		report += "\n"
	
	if not result.warnings.is_empty():
		report += "WARNINGS:\n"
		for warning in result.warnings:
			report += "  ⚠️ %s\n" % warning
		report += "\n"
	
	if not result.suggestions.is_empty():
		report += "SUGGESTIONS:\n"
		for suggestion in result.suggestions:
			report += "  💡 %s\n" % suggestion
	
	return report