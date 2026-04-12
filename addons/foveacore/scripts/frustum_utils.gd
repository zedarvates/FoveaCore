class_name FrustumUtils

## Plan de frustum (normal + distance)
class FrustumPlane:
	var normal: Vector3
	var distance: float

	func _init(p_normal: Vector3, p_distance: float):
		normal = p_normal.normalized()
		distance = p_distance

	func distance_to_point(point: Vector3) -> float:
		return normal.dot(point) + distance


## Frustum avec 6 plans
class Frustum:
	var planes: Array[FrustumPlane] = []

	func _init():
		for _i in range(6):
			planes.append(FrustumPlane.new(Vector3.ZERO, 0.0))

	## Extraire le frustum depuis la matrice de projection * vue
	func from_matrix(view_projection: Projection, camera_transform: Transform3D):
		# Matrice combinée
		var inv_transform: Transform3D = camera_transform.affine_inverse()
		var vp: Projection = view_projection * Projection(inv_transform)

		# Extraire les 6 plans
		# Left plane
		planes[0] = FrustumPlane.new(
			Vector3(vp.x.w + vp.x.x, vp.y.w + vp.y.x, vp.z.w + vp.z.x).normalized(),
			vp.w.w + vp.w.x
		)
		# Right plane
		planes[1] = FrustumPlane.new(
			Vector3(vp.x.w - vp.x.x, vp.y.w - vp.y.x, vp.z.w - vp.z.x).normalized(),
			vp.w.w - vp.w.x
		)
		# Bottom plane
		planes[2] = FrustumPlane.new(
			Vector3(vp.x.w + vp.x.y, vp.y.w + vp.y.y, vp.z.w + vp.z.y).normalized(),
			vp.w.w + vp.w.y
		)
		# Top plane
		planes[3] = FrustumPlane.new(
			Vector3(vp.x.w - vp.x.y, vp.y.w - vp.y.y, vp.z.w - vp.z.y).normalized(),
			vp.w.w - vp.w.y
		)
		# Near plane
		planes[4] = FrustumPlane.new(
			Vector3(vp.x.w + vp.x.z, vp.y.w + vp.y.z, vp.z.w + vp.z.z).normalized(),
			vp.w.w + vp.w.z
		)
		# Far plane
		planes[5] = FrustumPlane.new(
			Vector3(vp.x.w - vp.x.z, vp.y.w - vp.y.z, vp.z.w - vp.z.z).normalized(),
			vp.w.w - vp.w.z
		)

	## Tester si un AABB est dans le frustum
	func contains_aabb(aabb: AABB) -> bool:
		# Pour chaque plan, vérifier si l'AABB est entièrement dehors
		for plane in planes:
			# Calculer le point le plus positif de l'AABB par rapport au plan
			var center: Vector3 = aabb.position
			var extents: Vector3 = aabb.size / 2.0

			# Rayon projeté de l'AABB sur la normale du plan
			var radius: float = abs(extents.x * abs(plane.normal.x)) + \
						abs(extents.y * abs(plane.normal.y)) + \
						abs(extents.z * abs(plane.normal.z))

			# Distance du centre au plan
			var dist: float = plane.normal.dot(center) + plane.distance

			# Si la distance + rayon < 0, l'AABB est entièrement dehors
			if dist + radius < 0:
				return false

		return true

	## Tester si un point est dans le frustum
	func contains_point(point: Vector3) -> bool:
		for plane in planes:
			if plane.distance_to_point(point) < 0:
				return false
		return true

	## Tester si une sphère est dans le frustum
	func contains_sphere(center: Vector3, radius: float) -> bool:
		for plane in planes:
			if plane.distance_to_point(center) < -radius:
				return false
		return true
