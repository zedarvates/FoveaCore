extends Node
class_name StudioProcessor

## StudioProcessor — Video pre-processing for reconstruction
## Handles frame extraction and white background masking

signal frame_extracted(index: int, image: Image)
signal processing_completed(frame_count: int)
signal error_occurred(reason: String)

var ffmpeg_path: String = "ffmpeg"

## Extract frames from a video using FFmpeg
func extract_frames(session: ReconstructionSession) -> void:
	if session.video_path.is_empty():
		push_error("StudioProcessor: No video path provided.")
		return

	session.status = "Extracting Frames"
	var output_dir = ProjectSettings.globalize_path(session.output_directory + "/input")
	
	# Créer le répertoire de sortie s'il n'existe pas
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)

	var args = [
		"-i", ProjectSettings.globalize_path(session.video_path),
		"-vf", "fps=2", # Extraire 2 images par seconde pour le GS
		"-q:v", "2",     # Haute qualité
		output_dir + "/frame_%04d.jpg"
	]

	var cmd = ffmpeg_path if not ffmpeg_path.is_empty() else "ffmpeg"
	print("StudioProcessor: Executing -> ", cmd, " with args: ", args)
	var pid = OS.create_process(cmd, args)
	
	if pid == -1:
		var err_msg = "FFmpeg introuvable ou échec au lancement (Chemin: " + cmd + ")"
		push_error("StudioProcessor: " + err_msg)
		error_occurred.emit(err_msg)
		session.status = "Erreur"
		return

	while OS.is_process_running(pid):
		await get_tree().create_timer(0.5).timeout

	# Une fois FFmpeg terminé, on parcourt les images pour notifier le manager
	var dir = DirAccess.open(output_dir)
	var count = 0
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var frames = []
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".jpg"):
				frames.append(file_name)
			file_name = dir.get_next()
		
		# Sort frames to ensure correct order
		frames.sort()
		
		for i in range(frames.size()):
			var img = Image.load_from_file(output_dir + "/" + frames[i])
			if img:
				frame_extracted.emit(i, img)
				count += 1
	
	session.frame_count = count
	session.status = "Frames Extracted"
	processing_completed.emit(count)

## Extract a single frame for ROI preview
func get_preview_frame(video_path: String) -> Image:
	var temp_path = OS.get_user_data_dir() + "/fovea_preview.jpg"
	var args = [
		"-i", ProjectSettings.globalize_path(video_path),
		"-frames:v", "1",
		"-update", "1",
		"-y",
		ProjectSettings.globalize_path(temp_path)
	]
	
	var cmd = ffmpeg_path if not ffmpeg_path.is_empty() else "ffmpeg"
	var out = []
	var err = OS.execute(cmd, args, out)
	
	if err == -1:
		return null
		
	if FileAccess.file_exists(temp_path):
		var img = Image.load_from_file(temp_path)
		return img
		
	return null

## Background masking logic (moved from manager or implemented here)
func mask_background(image: Image, mode: String, threshold: float, roi: Rect2i) -> Image:
	var mask = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
	
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			# Check ROI
			if roi != Rect2i() and not roi.has_point(Vector2i(x, y)):
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
				continue
				
			var pixel = image.get_pixel(x, y)
			var is_background = false
			
			match mode:
				"Studio White":
					# If R, G, B are all high -> white/gray studio background
					is_background = (pixel.r > threshold and pixel.g > threshold and pixel.b > threshold)
				"Chroma Green":
					is_background = (pixel.g > pixel.r + 0.1 and pixel.g > pixel.b + 0.1)
				"Chroma Blue":
					is_background = (pixel.b > pixel.r + 0.1 and pixel.b > pixel.g + 0.1)
				"Smart Studio":
					# Advanced check taking saturation into account
					var hsv = _rgb_to_hsv(pixel)
					is_background = (hsv.y < 0.1 and hsv.z > threshold)
			
			mask.set_pixel(x, y, Color(0, 0, 0, 1) if is_background else Color(1, 1, 1, 1))
			
	return mask

func _rgb_to_hsv(c: Color) -> Vector3:
	# Simple hack for HSV conversion
	var max_v = max(c.r, max(c.g, c.b))
	var min_v = min(c.r, min(c.g, c.b))
	var delta = max_v - min_v
	
	var h = 0.0
	if delta > 0:
		if max_v == c.r: h = fmod((c.g - c.b) / delta, 6.0)
		elif max_v == c.g: h = (c.b - c.r) / delta + 2.0
		elif max_v == c.b: h = (c.r - c.g) / delta + 4.0
		h /= 6.0
		
	var s = 0.0 if max_v == 0 else delta / max_v
	var v = max_v
	return Vector3(h, s, v)
