class_name FoveaSplatCleaner
extends RefCounted

## FoveaEngine : Outil de nettoyage et décimation des splats (Sprint 1)
## Permet de filtrer les NaN, éliminer les floaters isolés et fusionner les splats superflus.

const SPLAT_BYTE_SIZE = 16

## Nettoie les NaN/Inf (fallback au niveau GDScript)
static func filter_nan_inf(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() == 0 or bytes.size() % SPLAT_BYTE_SIZE != 0:
		return bytes
		
	var out_bytes: PackedByteArray = PackedByteArray()
	var total_splats: int = bytes.size() / SPLAT_BYTE_SIZE
	out_bytes.resize(bytes.size())
	
	var valid_count: int = 0
	for i in range(total_splats):
		var offset: int = i * SPLAT_BYTE_SIZE
		var px: int = bytes.decode_u16(offset)
		var py: int = bytes.decode_u16(offset + 2)
		var pz: int = bytes.decode_u16(offset + 4)
		
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
		
	var total_splats: int = bytes.size() / SPLAT_BYTE_SIZE
	var out_bytes: PackedByteArray = PackedByteArray()
	
	# Voxelisation simplifiée pour la recherche de voisins proches
	# Diviser la grille en cellules de taille 128 (sur 65535)
	var voxel_size: int = 1024
	var grid: Dictionary = {}
	
	# Pass 1: Remplir la grille de voxels
	for i in range(total_splats):
		var offset: int = i * SPLAT_BYTE_SIZE
		var vx: int = int(bytes.decode_u16(offset) / voxel_size)
		var vy: int = int(bytes.decode_u16(offset + 2) / voxel_size)
		var vz: int = int(bytes.decode_u16(offset + 4) / voxel_size)
		
		var key: Vector3i = Vector3i(vx, vy, vz)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
		
	# Pass 2: Filtrer les splats isolés
	var surviving_indices: Array = []
	for key in grid.keys():
		var splats_in_cell: Array = grid[key]
		
		# Compter les voisins dans les cellules adjacentes
		var neighbors_count: int = 0
		for dx in range(-neighbor_radius_voxels, neighbor_radius_voxels + 1):
			for dy in range(-neighbor_radius_voxels, neighbor_radius_voxels + 1):
				for dz in range(-neighbor_radius_voxels, neighbor_radius_voxels + 1):
					var neighbor_key: Vector3i = key + Vector3i(dx, dy, dz)
					if grid.has(neighbor_key):
						neighbors_count += grid[neighbor_key].size()
						
		# Si la densité locale est trop faible, on marque ces splats comme floaters
		if neighbors_count >= min_neighbors:
			surviving_indices.append_array(splats_in_cell)
			
	# Construire le buffer final
	out_bytes.resize(surviving_indices.size() * SPLAT_BYTE_SIZE)
	for i in range(surviving_indices.size()):
		var src_offset: int = surviving_indices[i] * SPLAT_BYTE_SIZE
		var dst_offset: int = i * SPLAT_BYTE_SIZE
		for b in range(SPLAT_BYTE_SIZE):
			out_bytes[dst_offset + b] = bytes[src_offset + b]
			
	print("FoveaSplatCleaner: Floaters filtrés. %d -> %d splats." % [total_splats, surviving_indices.size()])
	return out_bytes

## Décime le nombre de splats en fusionnant les plus proches spatialement
static func decimate(bytes: PackedByteArray, target_count: int) -> PackedByteArray:
	if bytes.size() == 0 or bytes.size() / SPLAT_BYTE_SIZE <= target_count:
		return bytes
		
	var total_splats: int = bytes.size() / SPLAT_BYTE_SIZE
	var out_bytes: PackedByteArray = PackedByteArray()
	
	# On regroupe les splats proches dans une grille plus grossière et on les fusionne
	# Calculer la taille de cellule nécessaire pour atteindre la cible approximative
	var grid_res: int = int(pow(total_splats / float(target_count), 0.33) * 512.0)
	grid_res = max(512, grid_res)
	
	var grid: Dictionary = {}
	for i in range(total_splats):
		var offset: int = i * SPLAT_BYTE_SIZE
		var vx: int = int(bytes.decode_u16(offset) / grid_res)
		var vy: int = int(bytes.decode_u16(offset + 2) / grid_res)
		var vz: int = int(bytes.decode_u16(offset + 4) / grid_res)
		
		var key: Vector3i = Vector3i(vx, vy, vz)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(offset)
		
	# Fusionner chaque cellule en un seul splat moyen
	out_bytes.resize(grid.size() * SPLAT_BYTE_SIZE)
	var idx: int = 0
	
	for key in grid.keys():
		var offsets: Array = grid[key]
		var sum_x: float = 0.0
		var sum_y: float = 0.0
		var sum_z: float = 0.0
		var sum_opac: float = 0.0
		
		# Pour la couleur, la normale et la covariance, on prend le splat de plus haute opacité (représentatif)
		var max_opac_offset: int = offsets[0]
		var max_opac: int = 0
		
		for offset in offsets:
			sum_x += bytes.decode_u16(offset)
			sum_y += bytes.decode_u16(offset + 2)
			sum_z += bytes.decode_u16(offset + 4)
			var opac: int = bytes.decode_u8(offset + 12)
			sum_opac += opac
			
			if opac > max_opac:
				max_opac = opac
				max_opac_offset = offset
				
		var count: int = offsets.size()
		var avg_x: int = int(sum_x / count)
		var avg_y: int = int(sum_y / count)
		var avg_z: int = int(sum_z / count)
		var avg_opac: int = int(sum_opac / count)
		
		var dst: int = idx * SPLAT_BYTE_SIZE
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

## Fusionne les splats co-planaires proches pour réduire le GPU overdraw (Phase 3).
##
## "Co-planaire" est défini comme : même bucket de profondeur Z quantifié
## ET même bucket de normale (u,v octahédrale), dans la même cellule XY.
## Les groupes de taille >= min_group_size sont fondus en un splat centroïde
## qui représente toute la surface locale — réduction typique de 20-40%.
##
## @param bytes           Buffer PackedSplat 16 bytes post-culling
## @param z_bucket        Taille du bucket de profondeur Z (0..65535)
## @param normal_bucket   Taille du bucket de normale octahédrale (0..255)
## @param xy_bucket       Taille du bucket de regroupement XY spatial
## @param min_group_size  Nombre minimum de splats pour déclencher la fusion
## @returns Buffer fusionné (toujours valide, potentiellement plus court)
static func merge_coplanar(
		bytes: PackedByteArray,
		z_bucket: int        = 512,
		normal_bucket: int   = 24,
		xy_bucket: int       = 1024,
		min_group_size: int  = 4
) -> PackedByteArray:
	if bytes.is_empty():
		return bytes
	var total_splats: int = bytes.size() / SPLAT_BYTE_SIZE
	if total_splats < min_group_size * 2:
		return bytes  # Pas assez de splats pour profiter de la fusion

	# ── Pass 1 : Indexation dans une grille multi-dimensionnelle ────────────
	# Clé = (qx/xy_bucket, qy/xy_bucket, qz/z_bucket, nu/normal_bucket, nv/normal_bucket)
	# Cette clé regroupe les splats qui partagent la même position XY grossière,
	# la même profondeur Z, et la même orientation de surface.
	var grid: Dictionary = {}

	for i: int in range(total_splats):
		var off: int = i * SPLAT_BYTE_SIZE

		var qx: int = bytes.decode_u16(off)
		var qy: int = bytes.decode_u16(off + 2)
		var qz: int = bytes.decode_u16(off + 4)
		var nu: int = bytes.decode_u8(off + 6)   # Normal U (octahedral)
		var nv: int = bytes.decode_u8(off + 7)   # Normal V (octahedral)

		# Construire une clé entière combinée pour eviter Vector5i (inexistant)
		# On encode (bx, by, bz, bnu, bnv) dans un seul entier 64-bit via un hash compact
		var bx:  int = qx  / xy_bucket
		var by:  int = qy  / xy_bucket
		var bz:  int = qz  / z_bucket
		var bnu: int = nu  / normal_bucket
		var bnv: int = nv  / normal_bucket

		# Combinaison de hachage : on utilise un entier de taille suffisante
		# Plages : bx∈[0..63], by∈[0..63], bz∈[0..127], bnu∈[0..10], bnv∈[0..10]
		# → on peut tout tenir dans un seul int64 (GDScript: int est 64 bits)
		var key: int = bx | (by << 6) | (bz << 12) | (bnu << 19) | (bnv << 24)

		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)

	# ── Pass 2 : Fusion des groupes ──────────────────────────────────────────
	var out_bytes: PackedByteArray = PackedByteArray()
	out_bytes.resize(bytes.size())  # Worst case : aucune fusion
	var out_count: int = 0
	var merged_groups: int = 0

	for key: int in grid:
		var group: Array = grid[key]
		var n: int = group.size()

		if n < min_group_size:
			# Groupe trop petit → copier les splats tels quels
			for idx: int in group:
				var src: int = idx * SPLAT_BYTE_SIZE
				var dst: int = out_count * SPLAT_BYTE_SIZE
				for b: int in range(SPLAT_BYTE_SIZE):
					out_bytes[dst + b] = bytes[src + b]
				out_count += 1
		else:
			# Groupe suffisamment grand → fusionner en un splat centroïde
			var sum_x: float = 0.0
			var sum_y: float = 0.0
			var sum_z: float = 0.0
			var sum_opac: float = 0.0
			var max_opac: int = 0
			var dominant_off: int = group[0] * SPLAT_BYTE_SIZE

			for idx: int in group:
				var src: int = idx * SPLAT_BYTE_SIZE
				sum_x += float(bytes.decode_u16(src))
				sum_y += float(bytes.decode_u16(src + 2))
				sum_z += float(bytes.decode_u16(src + 4))
				var opac: int = bytes.decode_u8(src + 12)
				sum_opac += float(opac)
				if opac > max_opac:
					max_opac = opac
					dominant_off = src  # Splat le plus opaque = représentatif du groupe

			var avg_x: int = int(sum_x / float(n))
			var avg_y: int = int(sum_y / float(n))
			var avg_z: int = int(sum_z / float(n))
			var avg_opac: int = mini(255, int(sum_opac / float(n)))

			var dst: int = out_count * SPLAT_BYTE_SIZE

			# Position : centroïde du groupe
			out_bytes.encode_u16(dst,     avg_x)
			out_bytes.encode_u16(dst + 2, avg_y)
			out_bytes.encode_u16(dst + 4, avg_z)

			# Normale, couleur, covariance : copié du splat dominant (le plus opaque)
			for b: int in range(6, SPLAT_BYTE_SIZE):
				out_bytes[dst + b] = bytes[dominant_off + b]

			# Réinjecter l'opacité moyenne
			out_bytes.encode_u8(dst + 12, avg_opac)

			out_count += 1
			merged_groups += 1

	out_bytes.resize(out_count * SPLAT_BYTE_SIZE)
	var reduction_pct: float = (1.0 - float(out_count) / float(total_splats)) * 100.0
	print("FoveaSplatCleaner: merge_coplanar: %d → %d splats (-%d groupes, -%.1f%% overdraw)." % [
		total_splats, out_count, merged_groups, reduction_pct])
	return out_bytes
