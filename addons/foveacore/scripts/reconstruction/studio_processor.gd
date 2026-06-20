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
	if session.dry_run:
		print("[DRY RUN] Simulating frame extraction...")
		session.status = "Extracting Frames (Simulated)"
		await get_tree().create_timer(0.2).timeout
		
		for i in range(3):
			var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			frame_extracted.emit(i, img)
			await get_tree().create_timer(0.05).timeout
			
		session.frame_count = 3
		session.status = "Frames Extracted"
		processing_completed.emit(3)
		return

	if session.video_path.is_empty():
		push_error("StudioProcessor: No video path provided.")
		return

	session.status = "Extracting Frames"
	var temp_dir: String = ProjectSettings.globalize_path(session.output_directory + "/temp_extract")
	
	# Create temporary directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_recursive_absolute(temp_dir)

	var args: Array[String] = [
		"-y",
		"-i", ProjectSettings.globalize_path(session.video_path),
		"-vf", "fps=2", # Extraire 2 images par seconde pour le GS
		"-q:v", "2",     # Haute qualité
		temp_dir + "/frame_%04d.jpg"
	]

	var cmd: String = ffmpeg_path if not ffmpeg_path.is_empty() else "ffmpeg"
	print("StudioProcessor: Executing -> ", cmd, " with args: ", args)
	var pid: int = OS.create_process(cmd, args)
	
	if pid == -1:
		var err_msg: String = "FFmpeg introuvable ou échec au lancement (Chemin: " + cmd + ")"
		push_error("StudioProcessor: " + err_msg)
		error_occurred.emit(err_msg)
		session.status = "Erreur"
		return

	while OS.is_process_running(pid):
		await get_tree().create_timer(0.5).timeout

	# Une fois FFmpeg terminé, on parcourt les images pour notifier le manager
	var dir: DirAccess = DirAccess.open(temp_dir)
	var count: int = 0
	var frames: Array[String] = []
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".jpg"):
				frames.append(file_name)
			file_name = dir.get_next()
		
		# Sort frames to ensure correct order
		frames.sort()
		
		for i in range(frames.size()):
			var img: Image = Image.load_from_file(temp_dir + "/" + frames[i])
			if img:
				frame_extracted.emit(i, img)
				count += 1
			
			# Keep UI responsive every 5 frames
			if i % 5 == 0:
				await get_tree().create_timer(0.01).timeout
	
	# Clean up temporary files and folder
	if not frames.is_empty():
		for f: String in frames:
			DirAccess.remove_absolute(temp_dir.path_join(f))
		DirAccess.remove_absolute(temp_dir)
		print("StudioProcessor: Cleaned up temporary extraction folder: ", temp_dir)
	
	session.frame_count = count
	session.status = "Frames Extracted"
	processing_completed.emit(count)

## Extract a single frame for ROI preview (async, non-blocking)
func get_preview_frame(video_path: String) -> Image:
	var temp_path: String = OS.get_user_data_dir() + "/fovea_preview.jpg"
	var args: Array[String] = [
		"-i", ProjectSettings.globalize_path(video_path),
		"-frames:v", "1",
		"-update", "1",
		"-y",
		ProjectSettings.globalize_path(temp_path)
	]
	
	var cmd: String = ffmpeg_path if not ffmpeg_path.is_empty() else "ffmpeg"
	var pid: int = OS.create_process(cmd, args)
	
	if pid == -1:
		push_error("StudioProcessor: Failed to launch FFmpeg for preview")
		return null
	
	# Wait for FFmpeg to finish (async, yields engine control)
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.05).timeout
	
	if FileAccess.file_exists(temp_path):
		var img: Image = Image.load_from_file(temp_path)
		if img:
			return img
		
	return null

## Background masking logic (moved from manager or implemented here)
func mask_background(image: Image, mode: String, threshold: float, roi: Rect2i) -> Image:
	if mode == "None":
		var mask: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
		mask.fill(Color.WHITE)
		return mask

	# Essayer d'utiliser le GPU si disponible
	var gpu_mask: Image = _mask_background_gpu(image, mode, threshold, roi)
	if gpu_mask:
		return gpu_mask
		
	# Fallback CPU (lent)
	var mask: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if roi != Rect2i() and not roi.has_point(Vector2i(x, y)):
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
				continue
			var pixel: Color = image.get_pixel(x, y)
			var is_background: bool = (pixel.r > threshold and pixel.g > threshold and pixel.b > threshold) # Simplifié
			mask.set_pixel(x, y, Color(0, 0, 0, 1) if is_background else Color(1, 1, 1, 1))
	return mask

func _init_gpu() -> void:
	if _rd: return
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd: return
	
	var shader_file: RDShaderFile = preload("res://addons/foveacore/shaders/mask_background_gpu.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var err: String = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not err.is_empty():
		push_error("StudioProcessor: Error compiling mask_background_gpu.glsl: " + err)
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	if _shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)
	else:
		push_error("StudioProcessor: Failed to create _shader RID")


func _free_gpu() -> void:
	if _rd:
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
			_pipeline = RID()
		if _shader.is_valid():
			_rd.free_rid(_shader)
			_shader = RID()
		_rd.free()
		_rd = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_gpu()

func _mask_background_gpu(image: Image, mode: String, threshold: float, roi: Rect2i) -> Image:
	_init_gpu()
	if not _rd or not _pipeline.is_valid(): return null
	
	var width: int = image.get_width()
	var height: int = image.get_height()
	
	# Mapping mode to int
	var mode_int: int = 0
	if mode == "Chroma Green": mode_int = 1
	elif mode == "Chroma Blue": mode_int = 2
	elif mode == "Smart Studio": mode_int = 3

	# 1. Create Input Texture
	var fmt: RDTextureFormat = RDTextureFormat.new()
	fmt.width = width
	fmt.height = height
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	# Ensure image is in RGBA8 format for the GPU
	image.convert(Image.FORMAT_RGBA8)
	var input_tex: RID = _rd.texture_create(fmt, RDTextureView.new(), [image.get_data()])
	
	# 2. Create Output Texture (R8)
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	var output_tex: RID = _rd.texture_create(fmt, RDTextureView.new())
	
	# 3. Create Uniform Set
	var uniform_in: RDUniform = RDUniform.new()
	uniform_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_in.binding = 0
	uniform_in.add_id(input_tex)
	
	var uniform_out: RDUniform = RDUniform.new()
	uniform_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_out.binding = 1
	uniform_out.add_id(output_tex)
	
	var uniform_set: RID = _rd.uniform_set_create([uniform_in, uniform_out], _shader, 0)
	
	# 4. Push Constants (Params)
	var push_constants: PackedByteArray = PackedByteArray()
	push_constants.resize(24) # 6 * 4 bytes (float, int, 4*int)
	push_constants.encode_float(0, threshold)
	push_constants.encode_s32(4, mode_int)
	push_constants.encode_s32(8, roi.position.x)
	push_constants.encode_s32(12, roi.position.y)
	push_constants.encode_s32(16, roi.size.x)
	push_constants.encode_s32(20, roi.size.y)
	
	# 5. Compute
	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	_rd.compute_list_dispatch(compute_list, ceil(width / 8.0), ceil(height / 8.0), 1)
	_rd.compute_list_end()
	
	_rd.submit()
	_rd.sync()
	
	# 6. Readback
	var output_data: PackedByteArray = _rd.texture_get_data(output_tex, 0)
	var mask: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, output_data)
	
	# Cleanup local RIDs (expensive to do every frame, but safe for now)
	_rd.free_rid(input_tex)
	_rd.free_rid(output_tex)
	
	return mask

func _rgb_to_hsv(c: Color) -> Vector3:
	# Simple hack for HSV conversion
	var max_v: float = max(c.r, max(c.g, c.b))
	var min_v: float = min(c.r, min(c.g, c.b))
	var delta: float = max_v - min_v
	
	var h: float = 0.0
	if delta > 0:
		if max_v == c.r: h = fmod((c.g - c.b) / delta, 6.0)
		elif max_v == c.g: h = (c.b - c.r) / delta + 2.0
		elif max_v == c.b: h = (c.r - c.g) / delta + 4.0
		h /= 6.0
		
	var s: float = 0.0 if max_v == 0 else delta / max_v
	var v: float = max_v
	return Vector3(h, s, v)

func generate_normal_map_from_depth(depth_image: Image) -> Image:
	var normal_map: Image = Image.create(depth_image.get_width(), depth_image.get_height(), false, Image.FORMAT_RGB8)
	
	for y in range(1, depth_image.get_height() - 1):
		for x in range(1, depth_image.get_width() - 1):
			var d_l: float = depth_image.get_pixel(x - 1, y).r
			var d_r: float = depth_image.get_pixel(x + 1, y).r
			var d_u: float = depth_image.get_pixel(x, y - 1).r
			var d_d: float = depth_image.get_pixel(x, y + 1).r
			
			var vec: Vector3 = Vector3(
				(d_l - d_r) * 2.0,
				(d_u - d_d) * 2.0,
				1.0
			)
			vec = vec.normalized()
			
			var nx: float = (vec.x + 1.0) * 0.5
			var ny: float = (vec.y + 1.0) * 0.5
			var nz: float = (vec.z + 1.0) * 0.5
			
			normal_map.set_pixel(x, y, Color(nx, ny, nz))
	
	return normal_map

func mask_by_normal(normal_image: Image, top_facing_threshold: float = 0.7) -> Image:
	var mask: Image = Image.create(normal_image.get_width(), normal_image.get_height(), false, Image.FORMAT_L8)
	
	for y in range(normal_image.get_height()):
		for x in range(normal_image.get_width()):
			var normal: Color = normal_image.get_pixel(x, y)
			var ny: float = normal.g
			
			if ny >= top_facing_threshold:
				mask.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
	
	return mask

func calculate_blur_score(image: Image) -> float:
	"""Variance of Laplacian — standard blur detection.
	Returns [0, 1]: 1.0 = perfectly sharp, <0.2 = blurry/unusable.
	"""
	var w: int = image.get_width()
	var h: int = image.get_height()
	if w < 3 or h < 3:
		return 0.0

	var analytical_image: Image = image
	# Downsample for performance if image is large
	if w > 256 or h > 256:
		analytical_image = image.duplicate()
		analytical_image.resize(256, 256, Image.INTERPOLATE_BILINEAR)
		w = 256
		h = 256

	# Laplacian kernel: [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
	var laplacian_values: PackedFloat32Array = PackedFloat32Array()
	laplacian_values.resize(w * h)

	var lap_max: float = 0.0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c_l: Color = analytical_image.get_pixel(x-1, y)
			var lum_l: float = 0.299 * c_l.r + 0.587 * c_l.g + 0.114 * c_l.b
			var c_r: Color = analytical_image.get_pixel(x+1, y)
			var lum_r: float = 0.299 * c_r.r + 0.587 * c_r.g + 0.114 * c_r.b
			var c_u: Color = analytical_image.get_pixel(x, y-1)
			var lum_u: float = 0.299 * c_u.r + 0.587 * c_u.g + 0.114 * c_u.b
			var c_d: Color = analytical_image.get_pixel(x, y+1)
			var lum_d: float = 0.299 * c_d.r + 0.587 * c_d.g + 0.114 * c_d.b
			var c_c: Color = analytical_image.get_pixel(x, y)
			var lum_c: float = 0.299 * c_c.r + 0.587 * c_c.g + 0.114 * c_c.b
			
			var val: float = abs(lum_l + lum_r + lum_u + lum_d - 4.0 * lum_c)
			laplacian_values[y * w + x] = val
			if val > lap_max:
				lap_max = val

	if lap_max == 0.0:
		return 0.0  # totally flat image -> max blur

	# Variance (compute_pass)
	var mean: float = 0.0
	var n: float = float((w - 2) * (h - 2))
	for v: float in laplacian_values:
		mean += v
	mean /= n

	var variance: float = 0.0
	for v: float in laplacian_values:
		var d: float = v - mean
		variance += d * d
	variance /= n

	# Normalize to [0, 1]. Empirical threshold: variance > 0.002 = sharp
	var score: float = clamp(variance / 0.005, 0.0, 1.0)
	return score

func calculate_brightness_and_variance(image: Image) -> Dictionary:
	var w: int = image.get_width()
	var h: int = image.get_height()
	if w == 0 or h == 0:
		return {"brightness": 0.0, "variance": 0.0}
	
	var analytical_image: Image = image
	if w > 128 or h > 128:
		analytical_image = image.duplicate()
		analytical_image.resize(128, 128, Image.INTERPOLATE_BILINEAR)
		w = 128
		h = 128
		
	var total_lum: float = 0.0
	var lum_values: PackedFloat32Array = PackedFloat32Array()
	lum_values.resize(w * h)
	
	for y in range(h):
		for x in range(w):
			var c: Color = analytical_image.get_pixel(x, y)
			var lum: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			lum_values[y * w + x] = lum
			total_lum += lum
			
	var avg_brightness: float = total_lum / float(w * h)
	
	var sum_sq_diff: float = 0.0
	for lum: float in lum_values:
		var diff: float = lum - avg_brightness
		sum_sq_diff += diff * diff
		
	var variance: float = sum_sq_diff / float(w * h)
	return {"brightness": avg_brightness, "variance": variance}


func detect_surface_features(image: Image) -> Dictionary:
	var result: Dictionary = {
		"top_facing_areas": 0,
		"vertical_areas": 0,
		"bottom_facing_areas": 0,
		"total_pixels": image.get_width() * image.get_height()
	}
	
	var depth_image: Image = image
	
	for y in range(1, depth_image.get_height() - 1):
		for x in range(1, depth_image.get_width() - 1):
			var d_l: float = depth_image.get_pixel(x - 1, y).r
			var d_r: float = depth_image.get_pixel(x + 1, y).r
			var d_u: float = depth_image.get_pixel(x, y - 1).r
			var d_d: float = depth_image.get_pixel(x, y + 1).r
			
			var gradient_x: float = d_l - d_r
			var gradient_y: float = d_u - d_d
			var normal_y: float = gradient_y
			
			if normal_y > 0.2:
				result["top_facing_areas"] += 1
			elif normal_y < -0.2:
				result["bottom_facing_areas"] += 1
			else:
				result["vertical_areas"] += 1
	
	return result
