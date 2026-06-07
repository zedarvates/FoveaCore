extends Node3D
class_name HybridRenderer

## HybridRenderer — Combine mesh low-poly structurel + splats pour détails
## Rendu inédit : mesh pour la géométrie de base, splats pour la texture/pâte visuelle

## Configuration du rendu hybride
class HybridConfig:
	var mesh_enabled: bool = true
	var splat_enabled: bool = true
	var splat_offset: float = 0.01
	var mesh_opacity: float = 0.3
	var splat_density_override: float = 1.0
	var use_mesh_normals: bool = true
	var base_color: Color = Color(0.6, 0.55, 0.45)
	var material_type: int = StyleEngine.MaterialType.STONE

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
var _managed_meshes: Dictionary = {} # MeshInstance3D -> Array[Material]
var _splat_renderer = null
var _hybrid_material: StandardMaterial3D = null

## Initialiser le renderer hybride pour un nœud
func setup_for_node(mesh_node: MeshInstance3D, splat_renderer_node) -> void:
	if mesh_node == null:
		return
	_splat_renderer = splat_renderer_node

	if not _managed_meshes.has(mesh_node):
		var original_materials = []
		for i in range(mesh_node.get_surface_override_material_count()):
			original_materials.append(mesh_node.get_surface_override_material(i))
		_managed_meshes[mesh_node] = original_materials

	if _hybrid_material == null:
		# Créer le matériau hybride (semi-transparent)
		_hybrid_material = StandardMaterial3D.new()
		_hybrid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hybrid_material.albedo_color = Color(1, 1, 1, config.mesh_opacity)
		_hybrid_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_apply_mode_for_node(mesh_node)

## Appliquer le mode de rendu actuel à tous les nœuds
func _apply_mode() -> void:
	var to_remove = []
	for mesh in _managed_meshes:
		if not is_instance_valid(mesh):
			to_remove.append(mesh)
		else:
			_apply_mode_for_node(mesh)
	for mesh in to_remove:
		_managed_meshes.erase(mesh)

func _apply_mode_for_node(mesh_node: MeshInstance3D) -> void:
	match current_mode:
		RenderMode.MESH_ONLY:
			mesh_node.visible = true
			_restore_original_materials_for_node(mesh_node)
			if _splat_renderer:
				_splat_renderer.visible = false

		RenderMode.SPLAT_ONLY:
			# Rétablir la visibilité d'origine du mesh
			var parent = mesh_node.get_parent()
			if parent is FoveaSplattable:
				mesh_node.visible = not parent.hide_mesh_when_splatting
			else:
				var splattable = mesh_node.get_node_or_null("FoveaSplattable")
				if splattable and splattable is FoveaSplattable:
					mesh_node.visible = not splattable.hide_mesh_when_splatting
				else:
					mesh_node.visible = true
			_restore_original_materials_for_node(mesh_node)
			if _splat_renderer:
				_splat_renderer.visible = true

		RenderMode.HYBRID:
			mesh_node.visible = config.mesh_enabled
			_apply_hybrid_materials_for_node(mesh_node)
			if _splat_renderer:
				_splat_renderer.visible = config.splat_enabled

## Appliquer les matériaux hybrides (semi-transparents)
func _apply_hybrid_materials_for_node(mesh_node: MeshInstance3D) -> void:
	if _hybrid_material == null:
		return

	for i in range(mesh_node.get_surface_override_material_count()):
		mesh_node.set_surface_override_material(i, _hybrid_material)

## Restaurer les matériaux originaux
func _restore_original_materials_for_node(mesh_node: MeshInstance3D) -> void:
	if _managed_meshes.has(mesh_node):
		var original_materials = _managed_meshes[mesh_node]
		for i in range(original_materials.size()):
			mesh_node.set_surface_override_material(i, original_materials[i])

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
				splat.position = pos + normal * config.splat_offset
				splat.normal = normal
				# StyleEngine: compute procedural color from position + normal
				var style_config = StyleEngine.MaterialStyleConfig.new()
				style_config.base_color = config.base_color
				splat.color = StyleEngine.compute_color(pos, normal, config.material_type, style_config)
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
func set_mesh_opacity(opacity: float) -> void:
	config.mesh_opacity = clamp(opacity, 0.0, 1.0)
	if _hybrid_material:
		_hybrid_material.albedo_color.a = config.mesh_opacity

## Obtenir les stats
func get_stats() -> Dictionary:
	return {
		"mode": RenderMode.keys()[current_mode],
		"mesh_enabled": config.mesh_enabled,
		"splat_enabled": config.splat_enabled,
		"mesh_opacity": config.mesh_opacity
	}
