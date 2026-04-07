class_name SplatSorter

## SplatSorter - Tri et optimisation des splats pour le rendu
## Depth sorting + foveated rendering + overdraw minimization


## Trier les splats par profondeur (back-to-front pour alpha blending)
static func sort_by_depth(splats: Array[GaussianSplat], camera_position: Vector3) -> Array[GaussianSplat]:
	var sorted: Array[GaussianSplat] = splats.duplicate()

	# Mettre à jour les profondeurs
	for splat in sorted:
		splat.depth = splat.position.distance_to(camera_position)

	# Tri back-to-front (plus loin en premier)
	sorted.sort_custom(func(a: GaussianSplat, b: GaussianSplat) -> bool:
		return a.depth > b.depth
	)

	return sorted


## Appliquer le foveated rendering aux splats
static func apply_foveated_rendering(
	splats: Array[GaussianSplat],
	gaze_point: Vector3,
	foveal_radius: float,
	foveal_density: float = 2.0,
	parafoveal_density: float = 1.0,
	peripheral_density: float = 0.3
) -> Array[GaussianSplat]:
	var result: Array[GaussianSplat] = []

	for splat in splats:
		var distance_to_gaze: float = splat.position.distance_to(gaze_point)
		var weight: float

		if distance_to_gaze < foveal_radius:
			# Zone fovéale : densité max
			weight = 1.0
			splat.apply_foveal_weight(foveal_density / 2.0)
		elif distance_to_gaze < foveal_radius * 2.5:
			# Zone parafovéale : densité moyenne
			var t: float = (distance_to_gaze - foveal_radius) / (foveal_radius * 1.5)
			weight = lerp(1.0, 0.5, t)
			splat.apply_foveal_weight(parafoveal_density / 2.0)
		else:
			# Zone périphérique : densité faible
			weight = 0.3
			splat.apply_foveal_weight(peripheral_density / 2.0)

		# Filtrer les splats trop opaques en périphérie
		if splat.opacity > 0.05:
			result.append(splat)

	return result


## Minimiser l'overdraw en fusionnant les splats proches
static func minimize_overdraw(splats: Array[GaussianSplat], merge_threshold: float = 0.05) -> Array[GaussianSplat]:
	if splats.size() < 2:
		return splats

	var result: Array[GaussianSplat] = []
	var used: Dictionary = {}

	for i in range(splats.size()):
		if used.has(i):
			continue

		var splat: GaussianSplat = splats[i]
		var merged: bool = false

		# Chercher les splats proches à fusionner
		for j in range(i + 1, splats.size()):
			if used.has(j):
				continue

			var other: GaussianSplat = splats[j]
			var dist: float = splat.position.distance_to(other.position)

			if dist < merge_threshold:
				# Fusionner : moyenne pondérée
				var total_area: float = splat.radius * splat.radius + other.radius * other.radius
				var w1: float = (splat.radius * splat.radius) / total_area
				var w2: float = 1.0 - w1

				splat.position = splat.position * w1 + other.position * w2
				splat.color = Color(
					splat.color.r * w1 + other.color.r * w2,
					splat.color.g * w1 + other.color.g * w2,
					splat.color.b * w1 + other.color.b * w2,
					splat.color.a * w1 + other.color.a * w2
				)
				splat.radius = sqrt(splat.radius * splat.radius + other.radius * other.radius) * 0.8
				splat.normal = (splat.normal * w1 + other.normal * w2).normalized()

				used[j] = true
				merged = true

		result.append(splat)

	return result
