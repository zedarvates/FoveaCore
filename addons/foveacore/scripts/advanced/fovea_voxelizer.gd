class_name FoveaVoxelizer
extends RefCounted

## FoveaEngine : Voxeliseur et Générateur de Collision (Sprint 1)
## Construit une grille physique de collision à partir de la densité et de l'opacité des splats.
## Seuls les fichiers .fovea (format binaire natif FoveaCore) sont acceptés.

const SPLAT_BYTE_SIZE = 16

## Magic bytes attendus en tête de tout fichier .fovea valide
const FOVEA_MAGIC := "FOVEA_3D"
## Taille minimale = header (36 octets) + au moins 1 splat (16 octets)
const FOVEA_MIN_SIZE := 52

## Génère un CollisionShape3D (ConcavePolygonShape3D) pour les splats du fichier
static func generate_collision_shape(fovea_path: String, voxel_size_meters: float = 0.15, opacity_threshold: float = 0.1) -> Shape3D:
	var mesh = generate_voxel_mesh(fovea_path, voxel_size_meters, opacity_threshold)
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("FoveaVoxelizer: Échec de génération de la collision (aucun voxel solide).")
		return null
		
	# create_trimesh_shape génère automatiquement un ConcavePolygonShape3D optimal
	var shape = mesh.create_trimesh_shape()
	return shape

## Génère un maillage (ArrayMesh) représentant les voxels occupés.
## IMPORTANT: seuls les fichiers .fovea sont acceptés. Passer un .ply produirait
## une géométrie de collision corrompue sans erreur visible (BUG-02 fix).
static func generate_voxel_mesh(fovea_path: String, voxel_size_meters: float = 0.15, opacity_threshold: float = 0.1) -> ArrayMesh:
	# Guard 1 : vérification de l'extension
	if not fovea_path.ends_with(".fovea"):
		push_error("FoveaVoxelizer: Seuls les fichiers .fovea sont supportés. Reçu: '" + fovea_path + "'")
		return null

	if not FileAccess.file_exists(fovea_path):
		push_error("FoveaVoxelizer: Fichier introuvable: " + fovea_path)
		return null

	# Guard 2 : vérification du magic byte FOVEA_3D
	var check_file := FileAccess.open(fovea_path, FileAccess.READ)
	if check_file == null:
		push_error("FoveaVoxelizer: Impossible d'ouvrir le fichier: " + fovea_path)
		return null
	var file_size := check_file.get_length()
	if file_size < FOVEA_MIN_SIZE:
		push_error("FoveaVoxelizer: Fichier trop petit pour être valide (%d octets): %s" % [file_size, fovea_path])
		check_file.close()
		return null
	var magic_bytes := check_file.get_buffer(8)
	check_file.close()
	var magic_str := magic_bytes.get_string_from_ascii()
	if magic_str != FOVEA_MAGIC:
		push_error("FoveaVoxelizer: Magic byte invalide. Attendu '%s', obtenu '%s'. Fichier corrompu ou au mauvais format." % [FOVEA_MAGIC, magic_str])
		return null
		
	# 1. Obtenir les métadonnées (AABB et octets)
	var aabb = AABB(Vector3(-5,-5,-5), Vector3(10,10,10))
	var loader = null
	var raw_bytes = PackedByteArray()
	
	if ClassDB.can_instantiate("FoveaAssetLoader"):
		loader = ClassDB.instantiate("FoveaAssetLoader")
		if loader:
			aabb = loader.get_asset_aabb(fovea_path)
			raw_bytes = loader.load_fast_path(fovea_path)
			
	if raw_bytes.is_empty():
		# Fallback de secours si Rust n'est pas chargé
		var file = FileAccess.open(fovea_path, FileAccess.READ)
		if file:
			raw_bytes = file.get_buffer(file.get_length())
			file.close()
			
	if raw_bytes.is_empty():
		return null
		
	var total_splats = raw_bytes.size() / SPLAT_BYTE_SIZE
	var occupied_voxels = {}
	
	# 2. Voxelisation
	for i in range(total_splats):
		var offset = i * SPLAT_BYTE_SIZE
		var qx = raw_bytes.decode_u16(offset)
		var qy = raw_bytes.decode_u16(offset + 2)
		var pz = raw_bytes.decode_u16(offset + 4)
		var opacity = raw_bytes.decode_u8(offset + 12) / 255.0
		
		# Filtrer les splats transparents
		if opacity < opacity_threshold:
			continue
			
		# Décoder en coordonnées réelles
		var px = aabb.position.x + (float(qx) / 65535.0) * aabb.size.x
		var py = aabb.position.y + (float(qy) / 65535.0) * aabb.size.y
		var p_z = aabb.position.z + (float(pz) / 65535.0) * aabb.size.z
		
		var vx = int(floor(px / voxel_size_meters))
		var vy = int(floor(py / voxel_size_meters))
		var vz = int(floor(p_z / voxel_size_meters))
		
		var key = Vector3i(vx, vy, vz)
		occupied_voxels[key] = true
		
	if occupied_voxels.is_empty():
		return null
		
	# 3. Génération de géométrie (Triangles de cubes)
	# Pour optimiser, on n'ajoute que les faces extérieures
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	
	var face_dirs = [
		Vector3i(0, 0, 1),   # Avant
		Vector3i(0, 0, -1),  # Arrière
		Vector3i(1, 0, 0),   # Droite
		Vector3i(-1, 0, 0),  # Gauche
		Vector3i(0, 1, 0),   # Haut
		Vector3i(0, -1, 0)   # Bas
	]
	
	# Définition des coins locaux d'un cube (-0.5 à 0.5)
	var cube_corners = [
		Vector3(-0.5, -0.5,  0.5), # 0
		Vector3( 0.5, -0.5,  0.5), # 1
		Vector3( 0.5,  0.5,  0.5), # 2
		Vector3(-0.5,  0.5,  0.5), # 3
		Vector3(-0.5, -0.5, -0.5), # 4
		Vector3( 0.5, -0.5, -0.5), # 5
		Vector3( 0.5,  0.5, -0.5), # 6
		Vector3(-0.5,  0.5, -0.5)  # 7
	]
	
	# Indices des faces (2 triangles par face)
	var face_indices = [
		[0, 1, 2, 3], # Avant (+Z)
		[5, 4, 7, 6], # Arrière (-Z)
		[1, 5, 6, 2], # Droite (+X)
		[4, 0, 3, 7], # Gauche (-X)
		[3, 2, 6, 7], # Haut (+Y)
		[4, 5, 1, 0]  # Bas (-Y)
	]
	
	for voxel in occupied_voxels.keys():
		var center = Vector3(voxel) * voxel_size_meters + Vector3(voxel_size_meters, voxel_size_meters, voxel_size_meters) * 0.5
		
		for f in range(6):
			var neighbor = voxel + face_dirs[f]
			# Si le voisin n'est pas occupé, on dessine la face extérieure
			if not occupied_voxels.has(neighbor):
				var face = face_indices[f]
				var base_idx = vertices.size()
				
				# Ajouter les 4 sommets de la face
				for corner_idx in face:
					vertices.append(center + cube_corners[corner_idx] * voxel_size_meters)
					
				# Triangle 1
				indices.append(base_idx)
				indices.append(base_idx + 1)
				indices.append(base_idx + 2)
				# Triangle 2
				indices.append(base_idx)
				indices.append(base_idx + 2)
				indices.append(base_idx + 3)
				
	# 4. Assembler l'ArrayMesh
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_INDEX] = indices
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	
	print("FoveaVoxelizer: Physique générée. %d voxels solides -> %d triangles." % [occupied_voxels.size(), indices.size() / 3])
	return mesh
