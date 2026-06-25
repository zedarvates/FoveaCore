extends RefCounted
class_name FoveaLODTextureBaker

const FoveaSplattableScript = preload("res://addons/foveacore/scripts/fovea_splattable.gd")

## FoveaLODTextureBaker
## Projets les splats 3D sur l'espace UV d'un mesh low-poly et packe les textures en un atlas unique.

## Génère une texture 2D à partir des splats en les projetant sur les coordonnées UV du mesh
static func bake_splats_to_mesh_texture(
	splattable: Node,
	mesh: ArrayMesh,
	texture_size: int = 256,
	search_radius: float = 0.25,
	sigma: float = 0.1
) -> Image:
	var image: Image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	if splattable == null or mesh == null or not splattable.has_method("get") or splattable.get("loaded_splats").is_empty():
		return image

	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] or not arrays[Mesh.ARRAY_TEX_UV]:
		return image

	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()

	var splats: Array = splattable.get("loaded_splats")
	var grid: RefCounted = FoveaSplattableScript.SplatSpatialHashGrid.new(search_radius, splats)

	var num_triangles: int = indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for t in range(num_triangles):
		var i0: int
		var i1: int
		var i2: int
		if not indices.is_empty():
			i0 = indices[t * 3]
			i1 = indices[t * 3 + 1]
			i2 = indices[t * 3 + 2]
		else:
			i0 = t * 3
			i1 = t * 3 + 1
			i2 = t * 3 + 2

		# Bounds safety
		if i0 >= vertices.size() or i1 >= vertices.size() or i2 >= vertices.size():
			continue

		var p0: Vector3 = vertices[i0]
		var p1: Vector3 = vertices[i1]
		var p2: Vector3 = vertices[i2]

		var uv0: Vector2 = uvs[i0]
		var uv1: Vector2 = uvs[i1]
		var uv2: Vector2 = uvs[i2]

		# Limiter les UVs à l'espace [0, 1]
		var min_u: float = clampf(minf(uv0.x, minf(uv1.x, uv2.x)), 0.0, 1.0)
		var max_u: float = clampf(maxf(uv0.x, maxf(uv1.x, uv2.x)), 0.0, 1.0)
		var min_v: float = clampf(minf(uv0.y, minf(uv1.y, uv2.y)), 0.0, 1.0)
		var max_v: float = clampf(maxf(uv0.y, maxf(uv1.y, uv2.y)), 0.0, 1.0)

		var min_px: int = int(floor(min_u * texture_size))
		var max_px: int = int(ceil(max_u * texture_size))
		var min_py: int = int(floor(min_v * texture_size))
		var max_py: int = int(ceil(max_v * texture_size))

		# Parcourir chaque pixel de la boîte englobante UV
		for py in range(min_py, max_py):
			if py < 0 or py >= texture_size: continue
			for px in range(min_px, max_px):
				if px < 0 or px >= texture_size: continue

				# Coordonnées UV normalisées du centre du pixel
				var u: float = (px + 0.5) / texture_size
				var v: float = (py + 0.5) / texture_size
				var p_uv: Vector2 = Vector2(u, v)

				var bary: Vector3 = _get_barycentric(p_uv, uv0, uv1, uv2)
				if bary.x >= 0.0 and bary.y >= 0.0 and bary.z >= 0.0:
					# Position 3D interpolée sur la face
					var pos_3d: Vector3 = bary.x * p0 + bary.y * p1 + bary.z * p2

					# Trouver les splats à proximité
					var near_indices: Array[int] = []
					var raw_near = grid.call("get_indices_in_radius", pos_3d, search_radius)
					if raw_near is Array:
						for idx in raw_near:
							near_indices.append(int(idx))
							
					var color_sum: Color = Color(0, 0, 0, 0)
					var weight_sum: float = 0.0

					var sigma_sq: float = sigma * sigma
					for idx in near_indices:
						var splat: Object = splats[idx]
						var dist_sq: float = pos_3d.distance_squared_to(splat.get("position"))
						var opacity: float = float(splat.get("opacity"))
						var splat_color: Color = splat.get("color")
						var weight: float = exp(-dist_sq / (2.0 * sigma_sq)) * opacity
						color_sum += splat_color * weight
						weight_sum += weight

					if weight_sum > 0.001:
						var baked_color: Color = color_sum / weight_sum
						baked_color.a = 1.0
						image.set_pixel(px, py, baked_color)

	# Effectuer une passe de dilatation pour remplir les micro-trous aux coutures
	_dilate_texture(image)
	
	return image

## Calcule les coordonnées barycentriques d'un point P dans le triangle (A, B, C)
static func _get_barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0: Vector2 = b - a
	var v1: Vector2 = c - a
	var v2: Vector2 = p - a
	var d00: float = v0.dot(v0)
	var d01: float = v0.dot(v1)
	var d11: float = v1.dot(v1)
	var d20: float = v2.dot(v0)
	var d21: float = v2.dot(v1)
	var denom: float = d00 * d11 - d01 * d01
	if abs(denom) < 0.000001:
		return Vector3(-1.0, -1.0, -1.0)
	var v: float = (d11 * d20 - d01 * d21) / denom
	var w: float = (d00 * d21 - d01 * d20) / denom
	var u: float = 1.0 - v - w
	return Vector3(u, v, w)

## Dilate les pixels colorés sur les pixels transparents adjacents pour éviter les jointures noires
static func _dilate_texture(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var temp_image: Image = Image.create(width, height, false, image.get_format())
	temp_image.copy_from(image)

	# Helper directions
	var offsets: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

	for y in range(height):
		for x in range(width):
			var current: Color = image.get_pixel(x, y)
			if current.a > 0.01:
				continue

			var color_sum: Color = Color(0, 0, 0, 0)
			var count: int = 0
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx >= 0 and nx < width and ny >= 0 and ny < height:
					var n_color: Color = image.get_pixel(nx, ny)
					if n_color.a > 0.01:
						color_sum += n_color
						count += 1

			if count > 0:
				var avg_color: Color = color_sum / float(count)
				avg_color.a = 1.0
				temp_image.set_pixel(x, y, avg_color)

	image.copy_from(temp_image)

## Regroupe plusieurs images individuelles dans un atlas de texture unique
static func pack_textures_to_atlas(images: Array[Image], target_texture_size: int = 128) -> Dictionary:
	var count: int = images.size()
	if count == 0:
		return {
			"atlas_texture": null,
			"regions": [] as Array[Rect2]
		}

	var cols: int = int(ceil(sqrt(count)))
	var rows: int = int(ceil(float(count) / cols))

	var atlas_w: int = cols * target_texture_size
	var atlas_h: int = rows * target_texture_size

	var atlas_image: Image = Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color(0, 0, 0, 0))

	var regions: Array[Rect2] = []

	for i in range(count):
		var img: Image = images[i]
		
		# Redimensionner si nécessaire
		if img.get_width() != target_texture_size or img.get_height() != target_texture_size:
			# Créer une copie pour ne pas altérer l'image source
			var temp_img: Image = Image.create(img.get_width(), img.get_height(), false, img.get_format())
			temp_img.copy_from(img)
			temp_img.resize(target_texture_size, target_texture_size, Image.INTERPOLATE_LANCZOS)
			img = temp_img

		var col: int = i % cols
		var row: int = i / cols

		var x_offset: int = col * target_texture_size
		var y_offset: int = row * target_texture_size

		atlas_image.blit_rect(img, Rect2i(0, 0, target_texture_size, target_texture_size), Vector2i(x_offset, y_offset))

		var rx: float = float(x_offset) / atlas_w
		var ry: float = float(y_offset) / atlas_h
		var rw: float = float(target_texture_size) / atlas_w
		var rh: float = float(target_texture_size) / atlas_h
		regions.append(Rect2(rx, ry, rw, rh))

	var atlas_texture: ImageTexture = ImageTexture.create_from_image(atlas_image)

	return {
		"atlas_texture": atlas_texture,
		"regions": regions
	}
