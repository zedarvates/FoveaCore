extends RefCounted
class_name HierarchicalSplatGenerator

## HierarchicalSplatGenerator — Optimized splatting with Variable Sizes
## Large splats for base color, tiny splats for high-detail areas

## Generate splats by analyzing color variance across the mesh
static func generate_hierarchical_splats(mesh: Mesh, detail_threshold: float = 0.1) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []
	
	var arrays = mesh.surface_get_arrays(0)
	if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX]:
		return splats
		
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] else PackedColorArray()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] else PackedVector3Array()
	
	# Si pas de couleurs, initialiser à blanc
	if colors.is_empty():
		colors.resize(vertices.size())
		colors.fill(Color.WHITE)
		
	if normals.is_empty():
		normals.resize(vertices.size())
		normals.fill(Vector3.UP)
	
	# Track which areas have already been 'detailed'
	var detail_mask: Array[bool] = []
	detail_mask.resize(vertices.size())
	detail_mask.fill(false)
	
	# Construction d'une grille de hachage spatial
	var grid: Dictionary = {} # Vector3i -> Array[int]
	var cell_size: float = 0.15 # Voxel de 15 cm
	
	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		var gx := int(floor(v.x / cell_size))
		var gy := int(floor(v.y / cell_size))
		var gz := int(floor(v.z / cell_size))
		var key := Vector3i(gx, gy, gz)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	
	# 1. PASSE 1: Détection des zones de détail (Haute variance de couleur dans le voisinage 3D)
	for i in range(vertices.size()):
		var color: Color = colors[i]
		var v: Vector3 = vertices[i]
		
		# Récupérer les indices voisins dans les 27 cellules adjacentes
		var gx := int(floor(v.x / cell_size))
		var gy := int(floor(v.y / cell_size))
		var gz := int(floor(v.z / cell_size))
		
		var is_detailed := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var key := Vector3i(gx + dx, gy + dy, gz + dz)
					if grid.has(key):
						for n_idx: int in grid[key]:
							if n_idx != i:
								var n_v: Vector3 = vertices[n_idx]
								if v.distance_squared_to(n_v) < 0.05: # limite à ~22cm
									var n_color: Color = colors[n_idx]
									# Si la distance de couleur dépasse le seuil, marquer comme détail
									if _color_distance_squared(color, n_color) > (detail_threshold * detail_threshold):
										is_detailed = true
										break
				if is_detailed:
					break
			if is_detailed:
				break
				
		detail_mask[i] = is_detailed
				
	# 2. PASSE 2: Génération Hiérarchique (Macro-splats ou Micro-splats)
	for i in range(vertices.size()):
		var pos: Vector3 = vertices[i]
		var norm: Vector3 = normals[i]
		var col: Color = colors[i]
		
		if detail_mask[i]:
			# ZONE DE DÉTAIL: Petits splats denses et opaques
			for j in range(3): # Sous-échantillonnage pour plus de détails
				var splat := _create_splat(pos + _rand_vec(0.02), norm, col, 0.04)
				splats.append(splat)
		else:
			# ZONE UNIFORME: Grands splats clairsemés
			if i % 8 == 0: # Réduction de densité x8
				var splat := _create_splat(pos, norm, col, 0.18) # Splat de grande dimension
				splats.append(splat)
				
	return splats

static func _create_splat(pos: Vector3, norm: Vector3, col: Color, radius: float) -> GaussianSplat:
	var splat := GaussianSplat.new(pos)
	splat.normal = norm
	splat.surface_normal = norm
	splat.color = col
	splat.opacity = 0.95
	splat.scale = Vector3(radius, radius, radius * 0.1)
	
	if norm.length_squared() > 0.01:
		var up := Vector3.UP
		if abs(norm.dot(up)) > 0.99:
			up = Vector3.RIGHT
		splat.rotation = Quaternion(Basis.looking_at(norm, up))
		
	splat.compute_derived()
	return splat

static func _rand_vec(spread: float) -> Vector3:
	return Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))

static func _color_distance_squared(c1: Color, c2: Color) -> float:
	var dr := c1.r - c2.r
	var dg := c1.g - c2.g
	var db := c1.b - c2.b
	return dr * dr + dg * dg + db * db

