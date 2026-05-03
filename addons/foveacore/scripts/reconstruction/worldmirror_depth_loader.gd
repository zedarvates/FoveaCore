extends Node
class_name WorldMirrorDepthLoader

## WorldMirrorDepthLoader — Loads WorldMirror 2.0 depth maps for preview and analysis.
## Uses the PNG visualizations saved alongside .npy raw data.
## WM2 outputs: depth/depth_0000.png (norm. viz) + depth/depth_0000.npy (float32)

signal depth_loaded(frame_index: int, texture: ImageTexture)
signal all_depths_loaded(count: int)
signal error_occurred(message: String)

var _depth_textures: Array[ImageTexture] = []
var _depth_images: Array[Image] = []


func load_depth_maps(output_dir: String) -> Array[ImageTexture]:
	"""Load all depth PNG visualizations from a WM2 output directory."""
	_depth_textures.clear()
	_depth_images.clear()

	var depth_dir = output_dir.path_join("depth")
	var abs_dir = ProjectSettings.globalize_path(depth_dir)

	if not DirAccess.dir_exists_absolute(abs_dir):
		error_occurred.emit("Depth directory not found: " + abs_dir)
		return _depth_textures

	var dir = DirAccess.open(abs_dir)
	if not dir:
		error_occurred.emit("Cannot open depth directory")
		return _depth_textures

	dir.list_dir_begin()
	var files: Array[String] = []
	var fname = dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".png") and fname.begins_with("depth_"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()

	files.sort()

	for f in files:
		var full_path = depth_dir.path_join(f)
		var img = Image.load_from_file(ProjectSettings.globalize_path(full_path))
		if img:
			_depth_images.append(img)
			var tex = ImageTexture.create_from_image(img)
			_depth_textures.append(tex)

	print("WorldMirrorDepthLoader: Loaded %d depth maps" % _depth_textures.size())
	all_depths_loaded.emit(_depth_textures.size())
	return _depth_textures


func get_depth_texture(index: int) -> ImageTexture:
	if index < 0 or index >= _depth_textures.size():
		return null
	return _depth_textures[index]


func get_depth_image(index: int) -> Image:
	if index < 0 or index >= _depth_images.size():
		return null
	return _depth_images[index]


func get_depth_as_float32(index: int) -> PackedFloat32Array:
	"""Extract raw float32 depth values from PNG visualization.
	WM2 PNG depth encodes float32 Z-depth mapped to 0-255 (turbo colormap).
	For real values, use the .npy file (requires Python bridge).
	This provides a rough estimate by decoding the PNG pixel values.
	"""
	var img = get_depth_image(index)
	if not img:
		return PackedFloat32Array()

	var w = img.get_width()
	var h = img.get_height()
	var result = PackedFloat32Array()
	result.resize(w * h)

	for y in range(h):
		for x in range(w):
			var pixel = img.get_pixel(x, y)
			# WM2 PNGs use a colormap. We estimate depth from luminance.
			# Higher lum = closer (typically cooler colors = far, warm = close)
			var lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
			result[y * w + x] = lum

	return result


func count() -> int:
	return _depth_textures.size()


func clear() -> void:
	_depth_textures.clear()
	_depth_images.clear()
