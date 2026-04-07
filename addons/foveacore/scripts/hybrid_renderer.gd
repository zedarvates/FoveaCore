extends Node3D
class_name HybridRenderer

## HybridRenderer — Combine mesh low-poly structurel + splats pour détails
## Rendu inédit : mesh pour la géométrie de base, splats pour la texture/pâte visuelle

## Configuration du rendu hybride
class HybridConfig:
	var mesh_enabled: bool = true           # Activer le rendu mesh
	var splat_enabled: bool = true          # Activer le rendu splat
	var splat_offset: float = 0.01          # Décalage des splats au-dessus du mesh (éviter z-fighting)
	var mesh_opacity: float = 0.3           # Opacité du mesh (laissant voir les splats)
	var splat_density_override: float = 1.0 # Multiplicateur de densité pour le mode hybride
	var use_mesh_normals: bool = true       # Utiliser les normales du mesh pour orienter les splats

## Mode de rendu
enum RenderMode {
	MESH_ONLY,          # Uniquement le mesh (fallback)
	SPLAT_ONLY,         # Uniquement les splats (mode FoveaCore standard)
	HYBRID              # Mesh + splats combinés
}

## Configuration
var config: HybridConfig = HybridConfig.new()
var current_mode: RenderMode = RenderMode.HYBRID

## Références
var _mesh_instance: MeshInstance3D = null
var _splat_renderer = null
var _original_materials: Array = []
var _hybrid_material: StandardMaterial3D = null

## Initialiser le renderer hybride pour un nœud
func setup_for_node(mesh_node: MeshInstance3D, splat_renderer_node):
	_mesh_instance = mesh_node
	_splat_renderer = splat_renderer_node

	# Sauvegarder les matériaux originaux
	if _mesh_instance:
		for i in range(_mesh_instance.get_surface_override_material_count()):
			_original_materials.append(_mesh_instance.get_surface_override_material(i))

		# Créer le matériau hybride (semi-transparent)
		_hybrid_material = StandardMaterial3D.new()
		_hybrid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hybrid_material.albedo_color = Color(1, 1, 1, config.mesh_opacity)
		_hybrid_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_apply_mode()

## Appliquer le mode de rendu actuel
func _apply_mode():
	if _mesh_instance == null:
		return

	match current_mode:
		RenderMode.MESH_ONLY:
			_mesh_instance.visible = true
			_restore_original_materials()
			if _splat_renderer:
				_splat_renderer.visible = false

		RenderMode.SPLAT_ONLY:
			_mesh_instance.visible = false
			if _splat_renderer:
				_splat_renderer.visible = true

		RenderMode.HYBRID:
			_mesh_instance.visible = config.mesh_enabled
			_apply_hybrid_materials()
			if _splat_renderer:
				_splat_renderer.visible = config.splat_enabled

## Appliquer les matériaux hybrides (semi-transparents)
func _apply_hybrid_materials():
	if _hybrid_material == null:
		return

	for i in range(_mesh_instance.get_surface_override_material_count()):
		_mesh_instance.set_surface_override_material(i, _hybrid_material)

## Restaurer les matériaux originaux
func _restore_original_materials():
	for i in range(_original_materials.size()):
		_mesh_instance.set_surface_override_material(i, _original_materials[i])

## Générer les splats depuis la surface du mesh
func generate_splats_from_mesh(
	mesh: Mesh,
	splat_count: int = 1000,
	use_normals: bool = true
) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []

	if mesh == null:
		return splats

	# Parcourir les surfaces du mesh
	for surface_idx in range(mesh.get_surface_count()):
		var mesh_data = mesh.surface_get_arrays(surface_idx)
		if mesh_data.size() < Mesh.ARRAY_VERTEX:
			continue

		var vertices = mesh_data[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals = mesh_data[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var indices = mesh_data[Mesh.ARRAY_INDEX] as PackedInt32Array

		if vertices.is_empty():
			continue

		# Échantillonner des points sur les triangles
		var triangle_count = indices.size() / 3
		var splats_per_triangle = max(1, splat_count / max(triangle_count, 1))

		for i in range(0, indices.size() - 2, 3):
			var idx0 = indices[i]
			var idx1 = indices[i + 1]
			var idx2 = indices[i + 2]

			var v0 = vertices[idx0]
			var v1 = vertices[idx1]
			var v2 = vertices[idx2]

			# Générer des splats sur ce triangle
			for j in range(splats_per_triangle):
				# Échantillonnage barycentrique
				var r1 = randf()
				var r2 = randf()
				var sqrt_r1 = sqrt(r1)

				var u = 1.0 - sqrt_r1
				var v = sqrt_r1 * (1.0 - r2)
				var w = sqrt_r1 * r2

				var pos = v0 * u + v1 * v + v2 * w

				# Normale interpolée
				var normal = Vector3.UP
				if use_normals and normals.size() > max(idx0, max(idx1, idx2)):
					normal = (normals[idx0] * u + normals[idx1] * v + normals[idx2] * w).normalized()

				# Créer le splat
				var splat = GaussianSplat.new()
				splat.position = pos + normal * config.splat_offset  # Décalage pour éviter z-fighting
				splat.normal = normal
				splat.color = Color(0.7, 0.7, 0.7)  # Couleur par défaut, sera remplacée par StyleEngine
				splat.radius = 0.05
				splat.opacity = 1.0

				splats.append(splat)

	return splats

## Changer le mode de rendu
func set_mode(mode: RenderMode):
	current_mode = mode
	_apply_mode()

## Toggle mesh
func toggle_mesh(enabled: bool):
	config.mesh_enabled = enabled
	_apply_mode()

## Toggle splats
func toggle_splats(enabled: bool):
	config.splat_enabled = enabled
	_apply_mode()

## Ajuster l'opacité du mesh
func set_mesh_opacity(opacity: float):
	config.mesh_opacity = clamp(opacity, 0.0, 1.0)
	if current_mode == RenderMode.HYBRID:
		_hybrid_material.albedo_color.a = config.mesh_opacity

## Obtenir les stats
func get_stats() -> Dictionary:
	return {
		"mode": RenderMode.keys[current_mode],
		"mesh_enabled": config.mesh_enabled,
		"splat_enabled": config.splat_enabled,
		"mesh_opacity": config.mesh_opacity
	}
