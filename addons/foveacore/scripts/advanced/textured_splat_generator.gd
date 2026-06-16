extends Node
class_name TexturedSplatGenerator

## TexturedSplatGenerator — Advanced textured stamping (Sponge, Brushes)
## Replaces simple Gaussians with complex alpha masks for better material feel

const TEXTURE_DIR := "res://addons/foveacore/textures"

## Generate splats with textured brush types based on surface roughness
static func generate_textured_splats(mesh: Mesh) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []
	
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX]:
		return splats
		
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] else PackedVector3Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] else PackedColorArray()
	
	for i in range(vertices.size()):
		if i % 4 != 0: continue # Density reduction for textured splats
		
		var pos: Vector3 = vertices[i]
		var norm: Vector3 = normals[i] if normals.size() > i else Vector3.UP
		var col: Color = colors[i] if colors.size() > i else Color.WHITE
		
		var splat := GaussianSplat.new()
		splat.position = pos
		splat.normal = norm
		splat.color = col
		splat.radius = 0.08
		
		# LOGIQUE DE SÉLECTION DU PINCEAU:
		# On analyse la normale locale pour détecter la "rugosité"
		var roughness: float = _calculate_local_roughness(i, normals)
		
		if roughness > 0.6:
			splat.brush_type = GaussianSplat.BrushType.DRYBRUSH
		elif roughness > 0.4:
			splat.brush_type = GaussianSplat.BrushType.STONE
		elif roughness > 0.25:
			splat.brush_type = GaussianSplat.BrushType.SPONGE
		elif roughness > 0.12:
			splat.brush_type = GaussianSplat.BrushType.STIPPLE
		else:
			splat.brush_type = GaussianSplat.BrushType.GAUSSIAN
			
		splats.append(splat)
		
	return splats

static func _calculate_local_roughness(idx: int, normals: PackedVector3Array) -> float:
	if normals.is_empty() or normals.size() <= idx:
		return 0.0
	# Simuler un calcul de variance des normales
	var n1: Vector3 = normals[idx]
	var n2: Vector3 = normals[idx-1] if idx > 0 else n1
	return n1.distance_to(n2)

# --- Procedural Texture Generation & Loading ---

static func get_sponge_texture() -> Texture2D:
	return _get_or_create_texture("sponge.png", _generate_sponge_image)

static func get_drybrush_texture() -> Texture2D:
	return _get_or_create_texture("drybrush.png", _generate_drybrush_image)

static func get_stipple_texture() -> Texture2D:
	return _get_or_create_texture("stipple.png", _generate_stipple_image)

static func _get_or_create_texture(filename: String, generator: Callable) -> Texture2D:
	var path := TEXTURE_DIR.path_join(filename)
	
	# Try to load if it exists on disk
	if FileAccess.file_exists(path):
		var tex = load(path)
		if tex is Texture2D:
			return tex
			
	# Create directory if missing
	if not DirAccess.dir_exists_absolute(TEXTURE_DIR):
		DirAccess.make_dir_recursive_absolute(TEXTURE_DIR)
		
	# Generate procedural texture image
	var img: Image = generator.call()
	var err := img.save_png(path)
	if err == OK:
		# Use ImageTexture to load immediately without waiting for editor re-imports
		return ImageTexture.create_from_image(img)
		
	return ImageTexture.create_from_image(img)

static func apply_brush_textures(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("sponge_texture", get_sponge_texture())
	material.set_shader_parameter("drybrush_texture", get_drybrush_texture())
	material.set_shader_parameter("stipple_texture", get_stipple_texture())

# --- Math & Noise Helpers for Image Generation ---

static func _hash2d(x: int, y: int) -> float:
	var n := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return n - floor(n)

static func _smooth_noise(x: float, y: float) -> float:
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	var fx: float = x - floor(x)
	var fy: float = y - floor(y)
	
	var ux: float = fx * fx * (3.0 - 2.0 * fx)
	var uy: float = fy * fy * (3.0 - 2.0 * fy)
	
	var a := _hash2d(ix, iy)
	var b := _hash2d(ix + 1, iy)
	var c := _hash2d(ix, iy + 1)
	var d := _hash2d(ix + 1, iy + 1)
	
	return lerp(lerp(a, b, ux), lerp(c, d, ux), uy)

# --- Texture Image Generators ---

static func _generate_sponge_image() -> Image:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	for y in range(size):
		for x in range(size):
			var dx := (x - half) / half
			var dy := (y - half) / half
			var dist := sqrt(dx*dx + dy*dy)
			if dist > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
				
			var n1 := _smooth_noise(x * 0.15, y * 0.15)
			var n2 := _smooth_noise(x * 0.3, y * 0.3) * 0.5
			var noise_val = (n1 + n2) / 1.5
			
			var fade := 1.0 - dist
			var val := 0.0
			if noise_val > 0.4:
				val = fade
				
			img.set_pixel(x, y, Color(1, 1, 1, val))
	return img

static func _generate_drybrush_image() -> Image:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	for y in range(size):
		for x in range(size):
			var dx := (x - half) / half
			var dy := (y - half) / half
			var dist := sqrt(dx*dx + dy*dy)
			if dist > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
				
			var streak_y = y * 0.6
			var streak_x = x * 0.05
			var n1 := _smooth_noise(streak_x, streak_y)
			var n2 := _smooth_noise(streak_x * 2.0, streak_y * 2.0) * 0.4
			var noise_val = (n1 + n2) / 1.4
			
			var fade := 1.0 - dist
			var val := 0.0
			if noise_val > 0.35:
				val = fade
				
			img.set_pixel(x, y, Color(1, 1, 1, val))
	return img

static func _generate_stipple_image() -> Image:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	
	var centers := []
	var cells := 6
	var cell_size := size / float(cells)
	for cy in range(cells):
		for cx in range(cells):
			# Use deterministic hash to jitter dots
			var jitter_x = _hash2d(cx, cy) - 0.5
			var jitter_y = _hash2d(cy, cx) - 0.5
			var center_x: float = (cx + 0.5 + jitter_x * 0.6) * cell_size
			var center_y: float = (cy + 0.5 + jitter_y * 0.6) * cell_size
			
			var ndx := (center_x - half) / half
			var ndy := (center_y - half) / half
			if sqrt(ndx*ndx + ndy*ndy) < 0.85:
				centers.append(Vector2(center_x, center_y))
				
	for y in range(size):
		for x in range(size):
			var dx := (x - half) / half
			var dy := (y - half) / half
			var dist := sqrt(dx*dx + dy*dy)
			if dist > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
				
			var min_d := 9999.0
			var p := Vector2(x, y)
			for center in centers:
				var d_dot = p.distance_to(center)
				if d_dot < min_d:
					min_d = d_dot
					
			var fade := 1.0 - dist
			var val := 0.0
			var noise_rad = _smooth_noise(x * 0.2, y * 0.2)
			if min_d < 3.0 + 2.0 * noise_rad:
				val = fade
				
			img.set_pixel(x, y, Color(1, 1, 1, val))
	return img
