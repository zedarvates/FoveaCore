class_name OcclusionCuller

## OcclusionCuller - Culling d'occlusion via Hi-Z buffer (pyramide de profondeur)
## Évite de splatter ce qui est derrière un mur (+10-20% FPS)

## Configuration
class OcclusionConfig:
	var hi_z_resolution: Vector2i = Vector2i(256, 256)  # Résolution du Hi-Z buffer
	var max_mip_levels: int = 8                           # Niveaux de mip
	var depth_threshold: float = 0.01                     # Seuil de profondeur

## Pyramide de profondeur
var _hi_z_buffer: Array[Image] = []
var _viewport_size: Vector2i = Vector2i(1920, 1080)

## Configuration
var config: OcclusionConfig = OcclusionConfig.new()

## Construire la pyramide Hi-Z depuis le depth buffer
func build_hi_z_pyramid(depth_buffer: Image) -> void:
	_hi_z_buffer.clear()

	# Niveau 0 : depth buffer original (downscalé)
	var current: Image = depth_buffer.duplicate()
	current.resize(config.hi_z_resolution.x, config.hi_z_resolution.y)
	_hi_z_buffer.append(current)

	# Générer les mips
	for i in range(1, config.max_mip_levels):
		var prev: Image = _hi_z_buffer[i - 1]
		var mip: Image = Image.create(
			max(prev.get_width() / 2, 1),
			max(prev.get_height() / 2, 1),
			false,
			Image.FORMAT_RF
		)

		# Downscaler en prenant le min de profondeur (nearest)
		for y in range(mip.get_height()):
			for x in range(mip.get_width()):
				var src_x: int = x * 2
				var src_y: int = y * 2

				var min_depth: float = 1.0
				for dy in range(2):
					for dx in range(2):
						if src_x + dx < prev.get_width() and src_y + dy < prev.get_height():
							var d: float = prev.get_pixel(src_x + dx, src_y + dy).r
							min_depth = min(min_depth, d)

				mip.set_pixel(x, y, Color(min_depth, 0, 0, 1))

		_hi_z_buffer.append(mip)

## Tester si un point est occlus
func is_occluded(world_position: Vector3, view_projection: Projection, camera_transform: Transform3D) -> bool:
	if _hi_z_buffer.is_empty():
		return false

	# Transformer la position en espace écran
	var inv_transform: Transform3D = camera_transform.affine_inverse()
	var world_pos4: Vector4 = Vector4(world_position.x, world_position.y, world_position.z, 1.0)
	var clip_pos: Vector4 = view_projection * Projection(Transform3D(inv_transform.basis.inverse(), -inv_transform.basis.inverse() * inv_transform.origin)) * world_pos4
	if clip_pos.w <= 0:
		return false

	var ndc_pos: Vector3 = Vector3(clip_pos.x, clip_pos.y, clip_pos.z) / clip_pos.w

	# Coordonnées UV [0, 1]
	var uv: Vector2 = Vector2(
		ndc_pos.x * 0.5 + 0.5,
		1.0 - (ndc_pos.y * 0.5 + 0.5)
	)

	# Profondeur du point
	var point_depth: float = ndc_pos.z * 0.5 + 0.5

	# Sélectionner le niveau de mip approprié
	var mip_level: int = _select_mip_level(uv)
	if mip_level >= _hi_z_buffer.size():
		return false

	# Lire la profondeur du Hi-Z buffer
	var hi_z: Image = _hi_z_buffer[mip_level]
	var pixel_x: int = int(uv.x * hi_z.get_width())
	var pixel_y: int = int(uv.y * hi_z.get_height())

	pixel_x = clamp(pixel_x, 0, hi_z.get_width() - 1)
	pixel_y = clamp(pixel_y, 0, hi_z.get_height() - 1)

	var buffer_depth: float = hi_z.get_pixel(pixel_x, pixel_y).r

	# Si le point est derrière le buffer, il est occlus
	return point_depth > buffer_depth + config.depth_threshold

## Sélectionner le niveau de mip basé sur la taille de l'objet
func _select_mip_level(uv: Vector2) -> int:
	# Pour un point, utiliser le niveau le plus fin
	# Pour un objet plus grand, utiliser un niveau plus grossier
	return 0

## Tester si un AABB est occlus
func is_aabb_occluded(aabb: AABB, view_projection: Projection, camera_transform: Transform3D) -> bool:
	# Tester les 8 coins de l'AABB
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]

	var occluded_count: int = 0
	for corner in corners:
		if is_occluded(corner, view_projection, camera_transform):
			occluded_count += 1

	# Si tous les coins sont occlus, l'AABB est occlus
	return occluded_count == 8

## Réinitialiser
func clear() -> void:
	_hi_z_buffer.clear()
