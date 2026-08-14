extends RefCounted
class_name FoveaHLODGenerator

## FoveaHLODGenerator
## Classe utilitaire pour générer des niveaux de détail (HLOD) par fusion de centroïdes spatiaux (MIP-Splatting).
## Groupes de splats fusionnés dans des grilles de voxels pour réduire l'overdraw et le nombre d'instances à distance.

## Génère les niveaux HLOD sous forme de dictionnaire de tableaux de GaussianSplat
## Les clés du dictionnaire retourné sont :
## - 0 : Splats originaux (LOD 0)
## - 1 : LOD 1 (voxel_sizes[0])
## - 2 : LOD 2 (voxel_sizes[1])
## - 3 : LOD 3 (voxel_sizes[2])
static func generate_hlod_levels(original_splats: Array[GaussianSplat], voxel_sizes: Array[float]) -> Dictionary:
	var levels: Dictionary = {}
	
	# Le niveau 0 est toujours l'original
	levels[0] = original_splats
	if original_splats.is_empty():
		for i: int in range(voxel_sizes.size()):
			levels[i + 1] = [] as Array[GaussianSplat]
		return levels
	
	# Générer chaque niveau HLOD spécifié par les tailles de voxel
	for i: int in range(voxel_sizes.size()):
		var cell_size: float = voxel_sizes[i]
		var level_id: int = i + 1
		
		if cell_size <= 0.01:
			levels[level_id] = original_splats
			continue
			
		var cells: Dictionary = {} # Vector3i -> Array[GaussianSplat]
		
		# Voxelisation / Groupement spatial
		for s: GaussianSplat in original_splats:
			var gx: int = int(floor(s.position.x / cell_size))
			var gy: int = int(floor(s.position.y / cell_size))
			var gz: int = int(floor(s.position.z / cell_size))
			var key := Vector3i(gx, gy, gz)
			
			if not cells.has(key):
				cells[key] = [] as Array[GaussianSplat]
			cells[key].append(s)
			
		var simplified_splats: Array[GaussianSplat] = []
		
		# Fusionner chaque cellule de la grille
		for key: Vector3i in cells.keys():
			var cell_splats: Array[GaussianSplat] = cells[key]
			var count: int = cell_splats.size()
			
			var pos_sum := Vector3.ZERO
			var color_sum := Color(0.0, 0.0, 0.0, 0.0)
			var normal_sum := Vector3.ZERO
			var opacity_sum: float = 0.0
			
			# Rotation et épaisseur basées sur le splat le plus représentatif (plus opaque)
			var best_splat: GaussianSplat = cell_splats[0]
			var max_opacity: float = -1.0
			
			for s: GaussianSplat in cell_splats:
				pos_sum += s.position
				color_sum += s.color * s.opacity
				opacity_sum += s.opacity
				normal_sum += s.normal
				if s.opacity > max_opacity:
					max_opacity = s.opacity
					best_splat = s
					
			var avg_pos: Vector3 = pos_sum / float(count)
			var avg_normal: Vector3 = Vector3.UP
			if normal_sum.length_squared() > 0.001:
				avg_normal = normal_sum.normalized()
				
			var avg_color: Color = Color.WHITE
			if opacity_sum > 0.001:
				avg_color = Color(
					color_sum.r / opacity_sum,
					color_sum.g / opacity_sum,
					color_sum.b / opacity_sum
				)
			else:
				var temp_col := Color(0.0, 0.0, 0.0)
				for s: GaussianSplat in cell_splats:
					temp_col += s.color
				avg_color = temp_col / float(count)
				
			# Opacité moyenne boostée pour préserver l'opacité volumique cumulée
			var avg_opacity: float = opacity_sum / float(count)
			# Formule de compensation d'opacité cumulée pour combler la réduction de densité
			var merged_opacity: float = clampf(avg_opacity * 1.5, 0.1, 1.0)
			
			var merged_splat := GaussianSplat.new(avg_pos)
			merged_splat.color = avg_color
			merged_splat.opacity = merged_opacity
			merged_splat.normal = avg_normal
			merged_splat.rotation = best_splat.rotation
			
			# Calcul de l'échelle XY : proportionnelle à la taille du voxel
			var scale_xy: float = cell_size * 0.75
			var scale_z: float = best_splat.scale.z
			merged_splat.scale = Vector3(scale_xy, scale_xy, scale_z)
			
			merged_splat.compute_derived()
			simplified_splats.append(merged_splat)
			
		levels[level_id] = simplified_splats
		print("FoveaHLODGenerator: HLOD %d généré (Grille: %.2f m) : %d -> %d splats (%.1f%%)" % [
			level_id, cell_size, original_splats.size(), simplified_splats.size(), 
			float(simplified_splats.size()) / float(original_splats.size()) * 100.0
		])
		
	return levels
