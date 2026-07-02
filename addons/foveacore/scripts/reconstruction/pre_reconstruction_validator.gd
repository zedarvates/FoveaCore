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
	var result: ValidationResult = ValidationResult.new()
	validation_started.emit()
	
	validation_progress.emit("Checking file existence...", 5.0)
	if not FileAccess.file_exists(video_path):
		result.add_issue("Video file does not exist")
		validation_failed.emit("File not found")
		validation_completed.emit(result)
		return result
	
	validation_progress.emit("Analyzing video properties...", 20.0)
	var video_info: Dictionary = _get_video_info(video_path)
	if video_info.is_empty():
		result.add_issue("Unable to read video file")
		validation_failed.emit("Cannot read video")
		validation_completed.emit(result)
		return result
	
	_resolution_check(video_info, result)
	_framerate_check(video_info, result)
	_duration_check(video_info, result)
	_codec_check(video_info, result)
	
	validation_progress.emit("Extracting sample frames...", 50.0)
	var sample_frames: Array[Image] = _extract_sample_frames(video_path, 5)
	if sample_frames.is_empty():
		result.add_issue("Failed to extract frames from video")
		validation_failed.emit("Frame extraction failed")
		validation_completed.emit(result)
		return result
	
	validation_progress.emit("Analyzing lighting conditions...", 70.0)
	_analyze_lighting(sample_frames, result)
	
	validation_progress.emit("Checking background...", 85.0)
	_check_background_quality(sample_frames, result)
	
	result.score = clampf(result.score, 0.0, 100.0)
	
	validation_progress.emit("Validation complete", 100.0)
	validation_completed.emit(result)
	
	return result

func _get_video_info(path: String) -> Dictionary:
	var info: Dictionary = {}
	var args: Array[String] = [
		"-i", ProjectSettings.globalize_path(path),
		"-f", "null", "-"
	]
	var cmd: String = _processor.ffmpeg_path if not _processor.ffmpeg_path.is_empty() else "ffmpeg"
	var out: Array = []
	OS.execute(cmd, args, out)
	
	var output: String = " ".join(out)
	
	var res_match: RegEx = RegEx.new()
	res_match.compile("(\\d{2,5})x(\\d{2,5})")
	var match_result: RegExMatch = res_match.search(output)
	if match_result:
		info["width"] = int(match_result.get_string(1))
		info["height"] = int(match_result.get_string(2))
	
	var fps_match: RegEx = RegEx.new()
	fps_match.compile("(\\d+(?:\\.\\d+)?)\\s*fps")
	match_result = fps_match.search(output)
	if match_result:
		info["fps"] = float(match_result.get_string(1))
	
	var duration_match: RegEx = RegEx.new()
	duration_match.compile("Duration:\\s*(\\d+):(\\d+):(\\d+)\\.")
	match_result = duration_match.search(output)
	if match_result:
		var h: int = int(match_result.get_string(1))
		var m: int = int(match_result.get_string(2))
		var s: int = int(match_result.get_string(3))
		info["duration_seconds"] = h * 3600 + m * 60 + s
	
	var codec_match: RegEx = RegEx.new()
	codec_match.compile("Video:\\s*(\\w+)")
	match_result = codec_match.search(output)
	if match_result:
		info["codec"] = match_result.get_string(1)
	
	return info

func _resolution_check(info: Dictionary, result: ValidationResult) -> void:
	var width: int = info.get("width", 0) as int
	var height: int = info.get("height", 0) as int
	
	if width < 1280 or height < 720:
		result.add_issue("Resolution too low (minimum 1280x720 recommended). Current: %dx%d" % [width, height])
	elif width < 1920 or height < 1080:
		result.add_warning("Resolution below 1080p. Consider using higher resolution for better results.")
	else:
		result.add_suggestion("Resolution is good: %dx%d" % [width, height])

func _framerate_check(info: Dictionary, result: ValidationResult) -> void:
	var fps: float = info.get("fps", 0.0) as float
	
	if fps < 24.0:
		result.add_issue("Frame rate too low (minimum 24fps recommended). Current: %.1ffps" % fps)
	elif fps < 30.0:
		result.add_warning("Frame rate below 30fps. Consider using higher frame rate.")
	else:
		result.add_suggestion("High frame rate detected (%.1ffps). This will produce better results." % fps)

func _duration_check(info: Dictionary, result: ValidationResult) -> void:
	var duration: int = info.get("duration_seconds", 0) as int
	
	if duration < 3:
		result.add_issue("Video too short (minimum 3 seconds recommended). Current: %ds" % duration)
	elif duration < 10:
		result.add_warning("Short video. Consider using longer video for better reconstruction.")
	elif duration > 120:
		result.add_warning("Long video. Processing will take longer. Consider trimming to 30-60s.")
	else:
		result.add_suggestion("Duration is optimal: %ds" % duration)

func _codec_check(info: Dictionary, result: ValidationResult) -> void:
	var codec: String = info.get("codec", "") as String
	var supported: Array[String] = ["h264", "hevc", "av1", "vp9", "mpeg4"]
	
	if codec.is_empty():
		result.add_warning("Unable to detect video codec")
	elif codec.to_lower() not in supported:
		result.add_warning("Uncommon codec: %s. May cause issues." % codec)

func _extract_sample_frames(path: String, count: int) -> Array[Image]:
	var frames: Array[Image] = []
	var temp_dir: String = OS.get_user_data_dir() + "/fovea_validate_temp"
	
	if DirAccess.dir_exists_absolute(temp_dir):
		_delete_dir_recursive(temp_dir)
	DirAccess.make_dir_recursive_absolute(temp_dir)
	
	var duration: int = _get_video_info(path).get("duration_seconds", 10) as int
	var interval: int = max(duration / (count + 1), 1) as int
	
	for i: int in range(count):
		var timestamp: int = interval * (i + 1)
		var output_path: String = temp_dir + "/frame_%d.jpg" % i
		
		var args: Array[String] = [
			"-y",
			"-ss", str(timestamp),
			"-i", ProjectSettings.globalize_path(path),
			"-frames:v", "1",
			"-q:v", "2",
			ProjectSettings.globalize_path(output_path)
		]
		
		var cmd: String = _processor.ffmpeg_path if not _processor.ffmpeg_path.is_empty() else "ffmpeg"
		OS.execute(cmd, args, [])
		
		if FileAccess.file_exists(output_path):
			var img: Image = Image.load_from_file(output_path)
			if img:
				frames.append(img)
	
	if DirAccess.dir_exists_absolute(temp_dir):
		_delete_dir_recursive(temp_dir)
	
	return frames

func _delete_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path: String = path.path_join(file_name)
				if dir.current_is_dir():
					_delete_dir_recursive(full_path)
				else:
					DirAccess.remove_absolute(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)

func _analyze_lighting(frames: Array[Image], result: ValidationResult) -> void:
	var total_brightness: float = 0.0
	var sample_count: int = 0
	
	for frame: Image in frames:
		for y: int in range(0, frame.get_height(), 20):
			for x: int in range(0, frame.get_width(), 20):
				var pixel: Color = frame.get_pixel(x, y)
				var brightness: float = (pixel.r + pixel.g + pixel.b) / 3.0
				total_brightness += brightness
				sample_count += 1
	
	var avg_brightness: float = total_brightness / max(sample_count, 1)
	
	if avg_brightness < 0.2:
		result.add_issue("Video is too dark. Improve lighting conditions.")
	elif avg_brightness < 0.4:
		result.add_warning("Video is somewhat dark. Consider better lighting.")
	elif avg_brightness > 0.9:
		result.add_warning("Video may be overexposed. Check lighting.")
	else:
		result.add_suggestion("Lighting conditions are good (brightness: %.2f)" % avg_brightness)

func _check_background_quality(frames: Array[Image], result: ValidationResult) -> void:
	var studio_white_count: int = 0
	var chroma_green_count: int = 0
	
	for frame: Image in frames:
		var bg_pixels: int = 0
		var white_bg: int = 0
		var green_bg: int = 0
		
		for y: int in range(frame.get_height()):
			for x: int in range(frame.get_width()):
				var pixel: Color = frame.get_pixel(x, y)
				
				if pixel.r > 0.85 and pixel.g > 0.85 and pixel.b > 0.85:
					white_bg += 1
				elif pixel.g > pixel.r + 0.15 and pixel.g > pixel.b + 0.15:
					green_bg += 1
				
				bg_pixels += 1
		
		var white_ratio: float = float(white_bg) / float(bg_pixels)
		var green_ratio: float = float(green_bg) / float(bg_pixels)
		
		if white_ratio > 0.3:
			studio_white_count += 1
		if green_ratio > 0.3:
			chroma_green_count += 1
	
	var has_clean_bg: bool = studio_white_count >= frames.size() / 2 or chroma_green_count >= frames.size() / 2
	
	if not has_clean_bg:
		result.add_warning("No consistent clean background detected. Consider using studio white or chroma key green.")

func get_report_text(result: ValidationResult) -> String:
	var report: String = "=== Pre-Reconstruction Validation ===\n\n"
	report += "Score: %.0f/100\n" % result.score
	report += "Status: %s\n\n" % ("PASS" if result.is_valid else "FAIL")
	
	if not result.issues.is_empty():
		report += "ISSUES:\n"
		for issue: String in result.issues:
			report += "  ❌ %s\n" % issue
		report += "\n"
	
	if not result.warnings.is_empty():
		report += "WARNINGS:\n"
		for warning: String in result.warnings:
			report += "  ⚠️ %s\n" % warning
		report += "\n"
	
	if not result.suggestions.is_empty():
		report += "SUGGESTIONS:\n"
		for suggestion: String in result.suggestions:
			report += "  💡 %s\n" % suggestion
	
	return report