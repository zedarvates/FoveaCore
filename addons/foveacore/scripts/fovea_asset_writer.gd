extends RefCounted
class_name FoveaAssetWriter

## FoveaAssetWriter - Sérialiseur binaire pour le format .fovea
## Implémente la quantification de couleur (K-Means), la quantification de covariance (K-Means),
## l'ordonnancement de Morton spatial et l'écriture structurée de l'en-tête et des blocs.

const MAGIC: String = "FOVEA_3D"
const VERSION: int = 2

## Fonction principale pour écrire un fichier d'asset .fovea
static func write_fovea_asset(
	path: String,
	splats: Array[GaussianSplat],
	mesh: ArrayMesh = null,
	style: FoveaStyle = null,
	metadata: Dictionary = {}
) -> bool:
	if splats.is_empty():
		push_error("FoveaAssetWriter: Tentative d'écriture d'un asset sans splats.")
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FoveaAssetWriter: Impossible d'ouvrir le fichier en écriture: %s" % path)
		return false

	# 1. Calcul de l'AABB global des splats
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	for s: GaussianSplat in splats:
		aabb_min = aabb_min.min(s.position)
		aabb_max = aabb_max.max(s.position)
	
	# Ajouter une marge de sécurité
	aabb_min -= Vector3(0.01, 0.01, 0.01)
	aabb_max += Vector3(0.01, 0.01, 0.01)
	
	var range_x := maxf(aabb_max.x - aabb_min.x, 0.001)
	var range_y := maxf(aabb_max.y - aabb_min.y, 0.001)
	var range_z := maxf(aabb_max.z - aabb_min.z, 0.001)

	# 2. Quantification Vectorielle (K-Means)
	# Quantification des Couleurs (max 256)
	var color_k := clampi(256, 1, splats.size())
	var palette := quantize_colors(splats, color_k)
	
	# Quantification de la Covariance (max 1024)
	var covar_k := clampi(1024, 1, splats.size())
	var covar_codebook := quantize_covariances(splats, covar_k)

	# 3. Tri Spatial Morton
	var sorted_indices := range(splats.size())
	var morton_keys := PackedInt64Array()
	morton_keys.resize(splats.size())
	for i in range(splats.size()):
		var s := splats[i]
		var qx := int(clampf((s.position.x - aabb_min.x) / range_x * 65535.0, 0.0, 65535.0))
		var qy := int(clampf((s.position.y - aabb_min.y) / range_y * 65535.0, 0.0, 65535.0))
		var qz := int(clampf((s.position.z - aabb_min.z) / range_z * 65535.0, 0.0, 65535.0))
		morton_keys[i] = morton_encode_3d(qx >> 6, qy >> 6, qz >> 6)
		
	sorted_indices.sort_custom(func(a: int, b: int) -> bool:
		return morton_keys[a] < morton_keys[b]
	)

	# 4. Écriture temporaire de l'en-tête (on réécrira plus tard avec les bons offsets)
	# 72 octets d'en-tête vide/temporaire
	for i in range(72):
		file.store_8(0)

	# 5. Écriture de la Palette de Couleurs (RGB32F)
	# Palette de couleurs : color_k * 12 octets
	for col in palette:
		file.store_float(col.r)
		file.store_float(col.g)
		file.store_float(col.b)

	# 6. Écriture du Codebook de Covariance (32 octets par cluster std140)
	# Codebook de covariance : covar_k * 32 octets
	for dict in covar_codebook:
		var scale: Vector3 = dict["scale"]
		var rot: Quaternion = dict["rotation"]
		file.store_float(scale.x)
		file.store_float(scale.y)
		file.store_float(scale.z)
		file.store_float(rot.w)
		file.store_float(rot.x)
		file.store_float(rot.y)
		file.store_float(rot.z)
		file.store_float(0.0) # Padding d'alignement std140

	# 7. Écriture des Splats Compactés (16 octets/splat)
	for idx in sorted_indices:
		var s := splats[idx]
		
		# Position quantisée 16-bits
		var qx := int(clampf((s.position.x - aabb_min.x) / range_x * 65535.0, 0.0, 65535.0))
		var qy := int(clampf((s.position.y - aabb_min.y) / range_y * 65535.0, 0.0, 65535.0))
		var qz := int(clampf((s.position.z - aabb_min.z) / range_z * 65535.0, 0.0, 65535.0))
		
		file.store_16(qx)
		file.store_16(qy)
		file.store_16(qz)
		
		# Normale projetée signée 8-bits
		var nu := int(clampf(s.normal.x * 127.0, -128.0, 127.0))
		var nv := int(clampf(s.normal.z * 127.0, -128.0, 127.0))
		file.store_8(nu)
		file.store_8(nv)
		
		# Trouver le meilleur index de couleur dans la palette
		var best_color_idx := 0
		var min_dist := INF
		for j in range(palette.size()):
			var dr := s.color.r - palette[j].r
			var dg := s.color.g - palette[j].g
			var db := s.color.b - palette[j].b
			var d := dr*dr + dg*dg + db*db
			if d < min_dist:
				min_dist = d
				best_color_idx = j
		
		file.store_8(best_color_idx)
		file.store_8(0) # padding1
		
		# Trouver le meilleur index de covariance
		var best_covar_idx := 0
		var min_covar_dist := INF
		for j in range(covar_codebook.size()):
			var cent: Dictionary = covar_codebook[j]
			var cent_scale: Vector3 = cent["scale"]
			var cent_rot: Quaternion = cent["rotation"]
			var ds: float = (s.scale - cent_scale).length_squared()
			var dq: float = 1.0 - absf(s.rotation.dot(cent_rot))
			var d: float = ds + dq
			if d < min_covar_dist:
				min_covar_dist = d
				best_covar_idx = j
				
		file.store_16(best_covar_idx)
		
		# Opacité
		var op := int(clampf(s.opacity * 255.0, 0.0, 255.0))
		file.store_8(op)
		
		# Layer ID, dither seed, brush_type (shape type)
		file.store_8(int(s.layer_type))
		file.store_8(s.dither_seed)
		file.store_8(int(s.brush_type))

	# 8. Sections optionnelles
	var style_offset := 0
	var style_size := 0
	if style != null:
		style_offset = int(file.get_position())
		var style_dict := _serialize_style(style)
		var style_json := JSON.stringify(style_dict)
		var json_bytes := style_json.to_utf8_buffer()
		file.store_buffer(json_bytes)
		style_size = json_bytes.size()

	var mesh_offset := 0
	var mesh_size := 0
	if mesh != null:
		mesh_offset = int(file.get_position())
		mesh_size = _serialize_mesh(file, mesh)

	var meta_offset := 0
	var meta_size := 0
	if not metadata.is_empty():
		meta_offset = int(file.get_position())
		var meta_json := JSON.stringify(metadata)
		var json_bytes := meta_json.to_utf8_buffer()
		file.store_buffer(json_bytes)
		meta_size = json_bytes.size()

	# 9. Réécriture de l'en-tête finalisé au début du fichier
	file.seek(0)
	file.store_buffer(MAGIC.to_utf8_buffer()) # 8 bytes
	file.store_32(VERSION)
	file.store_32(splats.size())
	file.store_32(palette.size())
	file.store_32(covar_codebook.size())
	
	file.store_float(aabb_min.x)
	file.store_float(aabb_min.y)
	file.store_float(aabb_min.z)
	
	file.store_float(aabb_max.x)
	file.store_float(aabb_max.y)
	file.store_float(aabb_max.z)
	
	file.store_32(style_offset)
	file.store_32(style_size)
	file.store_32(mesh_offset)
	file.store_32(mesh_size)
	file.store_32(meta_offset)
	file.store_32(meta_size)

	file.close()
	print("FoveaAssetWriter: Asset écrit avec succès à '%s' (Splats: %d, Palette: %d, Covar: %d)." % [
		path, splats.size(), palette.size(), covar_codebook.size()
	])
	return true

## Quantification K-Means pour la palette de couleurs
static func quantize_colors(splats: Array[GaussianSplat], k: int) -> Array[Color]:
	var centroids: Array[Color] = []
	var n := splats.size()
	if n == 0:
		return centroids
		
	# Sélection initiale uniforme
	var step := max(1, n / k)
	for i in range(min(k, n)):
		centroids.append(splats[i * step].color)
		
	# 4 itérations de K-Means (compromis idéal vitesse/qualité)
	for iter in range(4):
		var sums_r := PackedFloat32Array()
		var sums_g := PackedFloat32Array()
		var sums_b := PackedFloat32Array()
		var counts := PackedInt32Array()
		sums_r.resize(centroids.size())
		sums_g.resize(centroids.size())
		sums_b.resize(centroids.size())
		counts.resize(centroids.size())
		
		for s in splats:
			var best_idx := 0
			var min_dist := INF
			var c := s.color
			for j in range(centroids.size()):
				var cent := centroids[j]
				var dr := c.r - cent.r
				var dg := c.g - cent.g
				var db := c.b - cent.b
				var d := dr*dr + dg*dg + db*db
				if d < min_dist:
					min_dist = d
					best_idx = j
			sums_r[best_idx] += c.r
			sums_g[best_idx] += c.g
			sums_b[best_idx] += c.b
			counts[best_idx] += 1
			
		for j in range(centroids.size()):
			if counts[j] > 0:
				centroids[j] = Color(sums_r[j] / counts[j], sums_g[j] / counts[j], sums_b[j] / counts[j])
				
	return centroids

## Quantification K-Means pour le codebook de covariance
static func quantize_covariances(splats: Array[GaussianSplat], k: int) -> Array[Dictionary]:
	var centroids: Array[Dictionary] = []
	var n := splats.size()
	if n == 0:
		return centroids
		
	var step := max(1, n / k)
	for i in range(min(k, n)):
		centroids.append({
			"scale": splats[i * step].scale,
			"rotation": splats[i * step].rotation
		})
		
	# 3 itérations de K-Means
	for iter in range(3):
		var sum_scale := []
		var sum_rot := []
		var counts := PackedInt32Array()
		sum_scale.resize(centroids.size())
		sum_rot.resize(centroids.size())
		counts.resize(centroids.size())
		for j in range(centroids.size()):
			sum_scale[j] = Vector3.ZERO
			sum_rot[j] = Quaternion(0, 0, 0, 0)
			
		for s in splats:
			var best_idx := 0
			var min_dist := INF
			for j in range(centroids.size()):
				var cent: Dictionary = centroids[j]
				var cent_scale: Vector3 = cent["scale"]
				var cent_rot: Quaternion = cent["rotation"]
				var ds: float = (s.scale - cent_scale).length_squared()
				var dot := s.rotation.dot(cent_rot)
				var dq: float = 1.0 - absf(dot)
				var d: float = ds + dq
				if d < min_dist:
					min_dist = d
					best_idx = j
			sum_scale[best_idx] += s.scale
			
			# Moyenne de quaternions (avec gestion du signe pour double couverture)
			var dot := s.rotation.dot(centroids[best_idx]["rotation"])
			if dot >= 0.0:
				sum_rot[best_idx] = Quaternion(
					sum_rot[best_idx].x + s.rotation.x,
					sum_rot[best_idx].y + s.rotation.y,
					sum_rot[best_idx].z + s.rotation.z,
					sum_rot[best_idx].w + s.rotation.w
				)
			else:
				sum_rot[best_idx] = Quaternion(
					sum_rot[best_idx].x - s.rotation.x,
					sum_rot[best_idx].y - s.rotation.y,
					sum_rot[best_idx].z - s.rotation.z,
					sum_rot[best_idx].w - s.rotation.w
				)
			counts[best_idx] += 1
			
		for j in range(centroids.size()):
			if counts[j] > 0:
				var avg_scale = sum_scale[j] / float(counts[j])
				var avg_rot = sum_rot[j].normalized()
				centroids[j] = {
					"scale": avg_scale,
					"rotation": avg_rot
				}
				
	return centroids

# Algorithmes Morton pour regroupement spatial
static func part_1_by_2(x: int) -> int:
	x &= 0x000003ff
	x = (x ^ (x << 16)) & 0xff0000ff
	x = (x ^ (x << 8))  & 0x0300f00f
	x = (x ^ (x << 4))  & 0x030c30c3
	x = (x ^ (x << 2))  & 0x09249249
	return x

static func morton_encode_3d(x: int, y: int, z: int) -> int:
	return (part_1_by_2(x) << 2) | (part_1_by_2(y) << 1) | part_1_by_2(z)

# Sérialisation auxiliaire des styles
static func _serialize_style(style: FoveaStyle) -> Dictionary:
	var dict := {
		"mode": style.mode,
		"detail": style.detail,
		"grain": style.grain,
		"light_coherence": style.light_coherence,
		"color_saturation": style.color_saturation,
		"micro_shadow": style.micro_shadow,
		"lora_path": style.lora_path,
		"neural_strength": style.neural_strength,
		"temporal_coherence": style.temporal_coherence,
	}
	if style.stone_params != null:
		dict["stone_params"] = _serialize_material(style.stone_params)
	if style.wood_params != null:
		dict["wood_params"] = _serialize_material(style.wood_params)
	if style.metal_params != null:
		dict["metal_params"] = _serialize_material(style.metal_params)
	if style.skin_params != null:
		dict["skin_params"] = _serialize_material(style.skin_params)
	return dict

static func _serialize_material(mat: FoveaMaterial) -> Dictionary:
	return {
		"material_type": int(mat.material_type),
		"base_color": [mat.base_color.r, mat.base_color.g, mat.base_color.b, mat.base_color.a],
		"roughness": mat.roughness,
		"metallic": mat.metallic,
		"bump_strength": mat.bump_strength,
		"specular_strength": mat.specular_strength,
		"noise_scale": mat.noise_scale,
		"noise_octaves": mat.noise_octaves,
		"noise_lacunarity": mat.noise_lacunarity,
		"noise_gain": mat.noise_gain
	}

# Sérialisation binaire d'un maillage unique
static func _serialize_mesh(file: FileAccess, mesh: ArrayMesh) -> int:
	var start_pos := file.get_position()
	if mesh.get_surface_count() == 0:
		file.store_32(0) # vertex_count
		file.store_32(0) # index_count
		file.store_8(0)  # has_normals
		file.store_8(0)  # has_uvs
		file.store_16(0) # padding
		return int(file.get_position() - start_pos)
		
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	
	var has_normals := 1 if arrays[Mesh.ARRAY_NORMAL] != null else 0
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if has_normals == 1 else PackedVector3Array()
	
	var has_uvs := 1 if arrays[Mesh.ARRAY_TEX_UV] != null else 0
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if has_uvs == 1 else PackedVector2Array()
	
	file.store_32(vertices.size())
	file.store_32(indices.size())
	file.store_8(has_normals)
	file.store_8(has_uvs)
	file.store_16(0) # padding
	
	for v in vertices:
		file.store_float(v.x)
		file.store_float(v.y)
		file.store_float(v.z)
		
	for idx in indices:
		file.store_32(idx)
		
	if has_normals == 1:
		for n in normals:
			file.store_float(n.x)
			file.store_float(n.y)
			file.store_float(n.z)
			
	if has_uvs == 1:
		for uv in uvs:
			file.store_float(uv.x)
			file.store_float(uv.y)
			
	return int(file.get_position() - start_pos)
