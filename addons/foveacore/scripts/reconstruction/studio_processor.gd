extends Node
class_name StudioProcessor

## StudioProcessor — Video pre-processing for reconstruction
## Handles frame extraction and white background masking

signal frame_extracted(index: int, image: Image)
signal processing_completed(frame_count: int)
signal error_occurred(reason: String)

var ffmpeg_path: String = "ffmpeg"

var _rd: RenderingDevice = null
var _shader: RID
var _pipeline: RID

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
			
			# Keep UI responsive every 5 frames
			if i % 5 == 0:
				await get_tree().process_frame
	
	session.frame_count = count
	session.status = "Frames Extracted"
	processing_completed.emit(count)

## Extract a single frame for ROI preview (async, non-blocking)
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
	var pid = OS.create_process(cmd, args)
	
	if pid == -1:
		push_error("StudioProcessor: Failed to launch FFmpeg for preview")
		return null
	
	# Wait for FFmpeg to finish (async, yields engine control)
	while OS.is_process_running(pid):
		await get_tree().process_frame
	
	if FileAccess.file_exists(temp_path):
		var img = Image.load_from_file(temp_path)
		return img if img else null
		return img
		
	return null

## Background masking logic (moved from manager or implemented here)
func mask_background(image: Image, mode: String, threshold: float, roi: Rect2i) -> Image:
	# Essayer d'utiliser le GPU si disponible
	var gpu_mask = _mask_background_gpu(image, mode, threshold, roi)
	if gpu_mask:
		return gpu_mask
		
	# Fallback CPU (lent)
	var mask = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if roi != Rect2i() and not roi.has_point(Vector2i(x, y)):
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
				continue
			var pixel = image.get_pixel(x, y)
			var is_background = (pixel.r > threshold and pixel.g > threshold and pixel.b > threshold) # Simplifié
			mask.set_pixel(x, y, Color(0, 0, 0, 1) if is_background else Color(1, 1, 1, 1))
	return mask

func _init_gpu() -> void:
	if _rd: return
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd: return
	
	var shader_file = load("res://addons/foveacore/shaders/mask_background_gpu.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)


func _free_gpu() -> void:
	if _rd:
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
			_pipeline = RID()
		if _shader.is_valid():
			_rd.free_rid(_shader)
			_shader = RID()
		if _rd:
			_rd = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_gpu()

func _mask_background_gpu(image: Image, mode: String, threshold: float, roi: Rect2i) -> Image:
	_init_gpu()
	if not _rd: return null
	
	var width = image.get_width()
	var height = image.get_height()
	
	# Mapping mode to int
	var mode_int = 0
	if mode == "Chroma Green": mode_int = 1
	elif mode == "Chroma Blue": mode_int = 2
	elif mode == "Smart Studio": mode_int = 3

	# 1. Create Input Texture
	var fmt = RDTextureFormat.new()
	fmt.width = width
	fmt.height = height
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	# Ensure image is in RGBA8 format for the GPU
	image.convert(Image.FORMAT_RGBA8)
	var input_tex = _rd.texture_create(fmt, RDTextureView.new(), [image.get_data()])
	
	# 2. Create Output Texture (R8)
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	var output_tex = _rd.texture_create(fmt, RDTextureView.new())
	
	# 3. Create Uniform Set
	var uniform_in = RDUniform.new()
	uniform_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_in.binding = 0
	uniform_in.add_id(input_tex)
	
	var uniform_out = RDUniform.new()
	uniform_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_out.binding = 1
	uniform_out.add_id(output_tex)
	
	var uniform_set = _rd.uniform_set_create([uniform_in, uniform_out], _shader, 0)
	
	# 4. Push Constants (Params)
	var push_constants = PackedByteArray()
	push_constants.resize(24) # 6 * 4 bytes (float, int, 4*int)
	push_constants.encode_float(0, threshold)
	push_constants.encode_s32(4, mode_int)
	push_constants.encode_s32(8, roi.position.x)
	push_constants.encode_s32(12, roi.position.y)
	push_constants.encode_s32(16, roi.size.x)
	push_constants.encode_s32(20, roi.size.y)
	
	# 5. Compute
	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	_rd.compute_list_dispatch(compute_list, ceil(width / 8.0), ceil(height / 8.0), 1)
	_rd.compute_list_end()
	
	_rd.submit()
	_rd.sync()
	
	# 6. Readback
	var output_data = _rd.texture_get_data(output_tex, 0)
	var mask = Image.create_from_data(width, height, false, Image.FORMAT_L8, output_data)
	
	# Cleanup local RIDs (expensive to do every frame, but safe for now)
	_rd.free_rid(input_tex)
	_rd.free_rid(output_tex)
	
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

func generate_normal_map_from_depth(depth_image: Image) -> Image:
	var normal_map = Image.create(depth_image.get_width(), depth_image.get_height(), false, Image.FORMAT_RGB8)
	
	for y in range(1, depth_image.get_height() - 1):
		for x in range(1, depth_image.get_width() - 1):
			var d_l = depth_image.get_pixel(x - 1, y).r
			var d_r = depth_image.get_pixel(x + 1, y).r
			var d_u = depth_image.get_pixel(x, y - 1).r
			var d_d = depth_image.get_pixel(x, y + 1).r
			
			var vec = Vector3(
				(d_l - d_r) * 2.0,
				(d_u - d_d) * 2.0,
				1.0
			)
			vec = vec.normalized()
			
			var nx = (vec.x + 1.0) * 0.5
			var ny = (vec.y + 1.0) * 0.5
			var nz = (vec.z + 1.0) * 0.5
			
			normal_map.set_pixel(x, y, Color(nx, ny, nz))
	
	return normal_map

func mask_by_normal(normal_image: Image, top_facing_threshold: float = 0.7) -> Image:
	var mask = Image.create(normal_image.get_width(), normal_image.get_height(), false, Image.FORMAT_L8)
	
	for y in range(normal_image.get_height()):
		for x in range(normal_image.get_width()):
			var normal = normal_image.get_pixel(x, y)
			var ny = normal.g
			
			if ny >= top_facing_threshold:
				mask.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
	
	return mask

func calculate_blur_score(image: Image) -> float:
	"""Variance of Laplacian — standard blur detection.
	Returns [0, 1]: 1.0 = perfectly sharp, <0.2 = blurry/unusable.
	"""
	var w := image.get_width()
	var h := image.get_height()
	if w < 3 or h < 3:
		return 0.0

	# Laplacian kernel: [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
	var laplacian_values := PackedFloat32Array()
	laplacian_values.resize(w * h)

	var lap_max := 0.0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var lum := func(px: int, py: int) -> float:
				var c := image.get_pixel(px, py)
				return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			var val := abs(lum.call(x-1, y) + lum.call(x+1, y) +
							lum.call(x, y-1) + lum.call(x, y+1) -
							4.0 * lum.call(x, y))
			laplacian_values[y * w + x] = val
			if val > lap_max:
				lap_max = val

	if lap_max == 0.0:
		return 0.0  # totally flat image -> max blur

	# Variance (compute_pass)
	var mean := 0.0
	var n := float((w - 2) * (h - 2))
	for v in laplacian_values:
		mean += v
	mean /= n

	var variance := 0.0
	for v in laplacian_values:
		var d := v - mean
		variance += d * d
	variance /= n

	# Normalize to [0, 1]. Empirical threshold: variance > 0.002 = sharp
	var score := clamp(variance / 0.005, 0.0, 1.0)
	return score

func detect_surface_features(image: Image) -> Dictionary:
	var result = {
		"top_facing_areas": 0,
		"vertical_areas": 0,
		"bottom_facing_areas": 0,
		"total_pixels": image.get_width() * image.get_height()
	}
	
	var depth_image = image
	
	for y in range(1, depth_image.get_height() - 1):
		for x in range(1, depth_image.get_width() - 1):
			var d_l = depth_image.get_pixel(x - 1, y).r
			var d_r = depth_image.get_pixel(x + 1, y).r
			var d_u = depth_image.get_pixel(x, y - 1).r
			var d_d = depth_image.get_pixel(x, y + 1).r
			
			var gradient_x = d_l - d_r
			var gradient_y = d_u - d_d
			var normal_y = gradient_y
			
			if normal_y > 0.2:
				result["top_facing_areas"] += 1
			elif normal_y < -0.2:
				result["bottom_facing_areas"] += 1
			else:
				result["vertical_areas"] += 1
	
	return result
