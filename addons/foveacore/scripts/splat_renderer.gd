extends Node3D
class_name SplatRenderer

## SplatRenderer - Rendu GPU des splats gaussiens
## Utilise des quads billboard avec un shader personnalisé

## Instance de mesh pour les splats
var _mesh_instance: MeshInstance3D = null
var _mesh: ImmediateMesh = null
var _material: ShaderMaterial = null

## Nombre de splats rendus
var _rendered_splats: int = 0


func _ready() -> void:
	_setup_mesh()
	_setup_material()


## Configurer le mesh
func _setup_mesh() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


## Configurer le matériau shader
func _setup_material() -> void:
	_material = ShaderMaterial.new()
	var shader: Shader = preload("res://addons/foveacore/shaders/splat_render.gdshader")
	_material.shader = shader
	_mesh_instance.material_override = _material


## Rendu des splats
func render_splats(splats: Array) -> int:
	if splats.is_empty():
		_mesh.clear_surfaces()
		_rendered_splats = 0
		return 0

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	for splat in splats:
		if not splat is GaussianSplat:
			continue
		if splat.opacity < 0.01:
			continue

		_render_splat(splat)

	_mesh.surface_end()
	_rendered_splats = splats.size()
	return _rendered_splats


## Rendu d'un splat individuel (quad billboard)
func _render_splat(splat: GaussianSplat) -> void:
	var pos: Vector3 = splat.position
	var radius: float = splat.radius
	var color: Color = splat.color
	var opacity: float = splat.opacity

	# Créer un quad billboard orienté vers la caméra
	var half_size: float = radius

	# Triangle 1
	# Sommet 0 (bas-gauche)
	_mesh.surface_set_uv(Vector2(0, 1))
	_mesh.surface_set_color(Color(color.r, color.g, color.b, opacity))
	_mesh.surface_add_vertex(pos + Vector3(-half_size, -half_size, 0))

	# Sommet 1 (bas-droite)
	_mesh.surface_set_uv(Vector2(1, 1))
	_mesh.surface_set_color(Color(color.r, color.g, color.b, opacity))
	_mesh.surface_add_vertex(pos + Vector3(half_size, -half_size, 0))

	# Sommet 2 (haut-gauche)
	_mesh.surface_set_uv(Vector2(0, 0))
	_mesh.surface_set_color(Color(color.r, color.g, color.b, opacity))
	_mesh.surface_add_vertex(pos + Vector3(-half_size, half_size, 0))

	# Triangle 2
	# Sommet 0 (bas-gauche)
	_mesh.surface_set_uv(Vector2(0, 1))
	_mesh.surface_set_color(Color(color.r, color.g, color.b, opacity))
	_mesh.surface_add_vertex(pos + Vector3(-half_size, -half_size, 0))

	# Sommet 1 (haut-droite)
	_mesh.surface_set_uv(Vector2(1, 0))
	_mesh.surface_set_color(Color(color.r, color.g, color.b, opacity))
	_mesh.surface_add_vertex(pos + Vector3(half_size, half_size, 0))

	# Sommet 2 (haut-gauche)
	_mesh.surface_set_uv(Vector2(0, 0))
	_mesh.surface_set_color(Color(color.r, color.g, color.b, opacity))
	_mesh.surface_add_vertex(pos + Vector3(-half_size, half_size, 0))


## Obtenir les statistiques
func get_stats() -> Dictionary:
	return {
		"rendered_splats": _rendered_splats,
		"mesh_instance": _mesh_instance != null
	}


## Nettoyer
func clear() -> void:
	if _mesh:
		_mesh.clear_surfaces()
	_rendered_splats = 0
