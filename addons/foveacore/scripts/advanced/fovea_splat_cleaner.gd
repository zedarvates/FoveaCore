class_name FoveaSplatCleaner
extends RefCounted

## FoveaEngine : Outil de nettoyage et décimation des splats (Sprint 1)
## Permet de filtrer les NaN, éliminer les floaters isolés et fusionner les splats superflus.

const SPLAT_BYTE_SIZE = 16

## Nettoie les NaN/Inf (fallback au niveau GDScript)
static func filter_nan_inf(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() == 0 or bytes.size() % SPLAT_BYTE_SIZE != 0:
		return bytes
		
	var out_bytes = PackedByteArray()
	var total_splats = bytes.size() / SPLAT_BYTE_SIZE
	out_bytes.resize(bytes.size())
	
	var valid_count = 0
	for i in range(total_splats):
		var offset = i * SPLAT_BYTE_SIZE
		var px = bytes.decode_u16(offset)
		var py = bytes.decode_u16(offset + 2)
		var pz = bytes.decode_u16(offset + 4)
		
		# Validation simple: si valeurs hors limites quantifiées extrêmes
		if px == 65535 and py == 65535 and pz == 65535:
			continue # Ignorer splat suspect
			
		for b in range(SPLAT_BYTE_SIZE):
			out_bytes[valid_count * SPLAT_BYTE_SIZE + b] = bytes[offset + b]
		valid_count += 1
		
	out_bytes.resize(valid_count * SPLAT_BYTE_SIZE)
	return out_bytes

## Filtre les floaters (splats "fantômes" isolés)
## Utilise une grille spatiale simplifiée pour trouver les splats qui n'ont pas de voisins proches
static func filter_floaters(bytes: PackedByteArray, neighbor_radius_voxels: int = 1, min_neighbors: int = 2) -> PackedByteArray:
	if bytes.size() == 0:
		return bytes
		
	var total_splats = bytes.size() / SPLAT_BYTE_SIZE
	var out_bytes = PackedByteArray()
	
	# Voxelisation simplifiée pour la recherche de voisins proches
	# Diviser la grille en cellules de taille 128 (sur 65535)
	var voxel_size = 1024
	var grid = {}
	
	# Pass 1: Remplir la grille de voxels
	for i in range(total_splats):
		var offset = i * SPLAT_BYTE_SIZE
		var vx = int(bytes.decode_u16(offset) / voxel_size)
		var vy = int(bytes.decode_u16(offset + 2) / voxel_size)
		var vz = int(bytes.decode_u16(offset + 4) / voxel_size)
		
		var key = Vector3i(vx, vy, vz)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
		
	# Pass 2: Filtrer les splats isolés
	var surviving_indices = []
	for key in grid.keys():
		var splats_in_cell = grid[key]
		
		# Compter les voisins dans les cellules adjacentes
		var neighbors_count = 0
		for dx in range(-neighbor_radius_voxels, neighbor_radius_voxels + 1):
			for dy in range(-neighbor_radius_voxels, neighbor_radius_voxels + 1):
				for dz in range(-neighbor_radius_voxels, neighbor_radius_voxels + 1):
					var neighbor_key = key + Vector3i(dx, dy, dz)
					if grid.has(neighbor_key):
						neighbors_count += grid[neighbor_key].size()
						
		# Si la densité locale est trop faible, on marque ces splats comme floaters
		if neighbors_count >= min_neighbors:
			surviving_indices.append_array(splats_in_cell)
			
	# Construire le buffer final
	out_bytes.resize(surviving_indices.size() * SPLAT_BYTE_SIZE)
	for i in range(surviving_indices.size()):
		var src_offset = surviving_indices[i] * SPLAT_BYTE_SIZE
		var dst_offset = i * SPLAT_BYTE_SIZE
		for b in range(SPLAT_BYTE_SIZE):
			out_bytes[dst_offset + b] = bytes[src_offset + b]
			
	print("FoveaSplatCleaner: Floaters filtrés. %d -> %d splats." % [total_splats, surviving_indices.size()])
	return out_bytes

## Décime le nombre de splats en fusionnant les plus proches spatialement
static func decimate(bytes: PackedByteArray, target_count: int) -> PackedByteArray:
	if bytes.size() == 0 or bytes.size() / SPLAT_BYTE_SIZE <= target_count:
		return bytes
		
	var total_splats = bytes.size() / SPLAT_BYTE_SIZE
	var out_bytes = PackedByteArray()
	
	# On regroupe les splats proches dans une grille plus grossière et on les fusionne
	# Calculer la taille de cellule nécessaire pour atteindre la cible approximative
	var grid_res = int(pow(total_splats / float(target_count), 0.33) * 512.0)
	grid_res = max(512, grid_res)
	
	var grid = {}
	for i in range(total_splats):
		var offset = i * SPLAT_BYTE_SIZE
		var vx = int(bytes.decode_u16(offset) / grid_res)
		var vy = int(bytes.decode_u16(offset + 2) / grid_res)
		var vz = int(bytes.decode_u16(offset + 4) / grid_res)
		
		var key = Vector3i(vx, vy, vz)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(offset)
		
	# Fusionner chaque cellule en un seul splat moyen
	out_bytes.resize(grid.size() * SPLAT_BYTE_SIZE)
	var idx = 0
	
	for key in grid.keys():
		var offsets = grid[key]
		var sum_x = 0.0
		var sum_y = 0.0
		var sum_z = 0.0
		var sum_opac = 0.0
		
		# Pour la couleur, la normale et la covariance, on prend le splat de plus haute opacité (représentatif)
		var max_opac_offset = offsets[0]
		var max_opac = 0
		
		for offset in offsets:
			sum_x += bytes.decode_u16(offset)
			sum_y += bytes.decode_u16(offset + 2)
			sum_z += bytes.decode_u16(offset + 4)
			var opac = bytes.decode_u8(offset + 12)
			sum_opac += opac
			
			if opac > max_opac:
				max_opac = opac
				max_opac_offset = offset
				
		var count = offsets.size()
		var avg_x = int(sum_x / count)
		var avg_y = int(sum_y / count)
		var avg_z = int(sum_z / count)
		var avg_opac = int(sum_opac / count)
		
		var dst = idx * SPLAT_BYTE_SIZE
		# Écriture de la position moyenne
		out_bytes.encode_u16(dst, avg_x)
		out_bytes.encode_u16(dst + 2, avg_y)
		out_bytes.encode_u16(dst + 4, avg_z)
		
		# Copie des autres attributs (normale, couleur, covariance, layer, dither) du splat dominant
		for b in range(6, SPLAT_BYTE_SIZE):
			out_bytes[dst + b] = bytes[max_opac_offset + b]
			
		# Ré-injecter l'opacité moyenne
		out_bytes.encode_u8(dst + 12, avg_opac)
		idx += 1
		
	print("FoveaSplatCleaner: Décimation terminée. %d -> %d splats." % [total_splats, idx])
	return out_bytes
