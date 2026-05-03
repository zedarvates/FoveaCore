class_name StyleEngine

## StyleEngine - Orchestrateur du style procédural pour FoveaCore
## Génère les couleurs et apparences des splats sans textures PBR

## Types de matériaux
enum MaterialType {
	STONE,
	WOOD,
	METAL,
	SKIN,
	FABRIC,
	GLASS,
	CUSTOM
}

## Configuration d'un style matériau
class MaterialStyleConfig:
	var material_type: MaterialType = MaterialType.STONE
	var base_color: Color = Color(0.5, 0.5, 0.5)
	var detail: float = 1.0
	var grain: float = 0.5
	var light_coherence: float = 0.8
	var micro_shadow: float = 0.5
	var specular_strength: float = 0.3
	var bump_strength: float = 0.5
	var noise_scale: float = 10.0
	var noise_octaves: int = 4
	var noise_lacunarity: float = 2.0
	var noise_gain: float = 0.5

## Cache des styles
static var _style_cache: Dictionary = {}

## Obtenir la couleur procédurale pour un point
static func compute_color(
	position: Vector3,
	normal: Vector3,
	material_type: MaterialType,
	config: MaterialStyleConfig,
	light_direction: Vector3 = Vector3(0, 1, 0.5).normalized()
) -> Color:
	var base = config.base_color

	match material_type:
		MaterialType.STONE:
			return _compute_stone_color(position, normal, base, config, light_direction)
		MaterialType.WOOD:
			return _compute_wood_color(position, normal, base, config, light_direction)
		MaterialType.METAL:
			return _compute_metal_color(position, normal, base, config, light_direction)
		MaterialType.SKIN:
			return _compute_skin_color(position, normal, base, config, light_direction)
		MaterialType.FABRIC:
			return _compute_fabric_color(position, normal, base, config, light_direction)
		MaterialType.GLASS:
			return _compute_glass_color(position, normal, base, config, light_direction)
		_:
			return _compute_custom_color(position, normal, base, config, light_direction)

## Obtenir la rugosité implicite
static func compute_roughness(
	position: Vector3,
	normal: Vector3,
	material_type: MaterialType,
	config: MaterialStyleConfig
) -> float:
	match material_type:
		MaterialType.STONE:
			return 0.7 + _fbm(position * config.noise_scale * 0.5, 2) * 0.3
		MaterialType.WOOD:
			return 0.5 + _fbm(position * config.noise_scale * 0.3, 2) * 0.3
		MaterialType.METAL:
			return 0.2 + _fbm(position * config.noise_scale * 0.2, 2) * 0.2
		MaterialType.SKIN:
			return 0.4 + _fbm(position * config.noise_scale * 0.5, 2) * 0.2
		MaterialType.GLASS:
			return 0.05  # Glass is perfectly smooth
		_:
			return 0.5

## Obtenir le specular implicite
static func compute_specular(
	position: Vector3,
	normal: Vector3,
	view_direction: Vector3,
	light_direction: Vector3,
	material_type: MaterialType,
	config: MaterialStyleConfig
) -> float:
	var half_vector = (view_direction + light_direction).normalized()
	var ndoth = max(normal.dot(half_vector), 0.0)
	var roughness = compute_roughness(position, normal, material_type, config)
	var specular_power = pow(1.0 - roughness, 4.0) * 128.0
	return pow(ndoth, max(specular_power, 1.0)) * config.specular_strength

## Obtenir le bump implicite (perturbation de normale)
static func compute_bump(
	position: Vector3,
	normal: Vector3,
	material_type: MaterialType,
	config: MaterialStyleConfig
) -> Vector3:
	var bump_strength = config.bump_strength * 0.1
	var scale = config.noise_scale * 2.0

	# Gradient du noise pour simuler le bump
	var dx = _fbm((position + Vector3(0.01, 0, 0)) * scale, config.noise_octaves) - \
			 _fbm((position - Vector3(0.01, 0, 0)) * scale, config.noise_octaves)
	var dz = _fbm((position + Vector3(0, 0, 0.01)) * scale, config.noise_octaves) - \
			 _fbm((position - Vector3(0, 0, 0.01)) * scale, config.noise_octaves)

	var bumped_normal = normal + Vector3(dx, 0, dz) * bump_strength
	return bumped_normal.normalized()

# ============================================================================
# STYLES SPÉCIFIQUES
# ============================================================================

## Style Pierre : FBM + Worley + micro-shadowing
static func _compute_stone_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var scale = config.noise_scale
	var octaves = config.noise_octaves

	# FBM pour la variation de base
	var fbm_val = _fbm(position * scale, octaves)

	# Worley noise pour les cellules de pierre
	var worley = _worley_noise(position * scale * 0.5)

	# Combiner les deux
	var variation = fbm_val * 0.6 + worley * 0.4

	# Appliquer la variation à la couleur de base
	var color = base * (0.7 + variation * 0.6 * config.detail)

	# Micro-shadowing basé sur la normale et la lumière
	var ndotl = max(normal.dot(light_dir), 0.0)
	var shadow = lerpf(config.micro_shadow, 1.0, ndotl)
	color = color * shadow

	# Grain
	var grain_noise = _simple_noise(position * scale * 5.0) * config.grain * 0.1
	color = color + Color(grain_noise, grain_noise, grain_noise)

	return color.clamp(Color(0, 0, 0), Color(1, 1, 1))

## Style Bois : Noise directionnel + sinusoïdes (anneaux)
static func _compute_wood_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var scale = config.noise_scale

	# Direction du grain (aligné sur l'axe Y par défaut)
	var grain_direction = Vector3(0, 1, 0)
	var distance_along_grain = position.dot(grain_direction)

	# Anneaux du bois (sinusoïdes déformées)
	var ring_frequency = 3.0 * config.detail
	var ring_phase = distance_along_grain * ring_frequency

	# Déformation fractale des anneaux
	var distortion = _fbm(position * scale * 0.5, 3) * 0.5
	var ring_value = sin(ring_phase + distortion * 3.14159 * 2.0)
	ring_value = ring_value * 0.5 + 0.5  # [0, 1]

	# Couleur de base avec variation des anneaux
	var dark_wood = base * 0.6
	var light_wood = base * 1.2
	var color = dark_wood.lerp(light_wood, ring_value)

	# Noise directionnel pour le grain
	var grain_noise = _directional_noise(position, grain_direction, scale) * config.grain * 0.15
	color = color + Color(grain_noise, grain_noise * 0.8, grain_noise * 0.6)

	# Micro-shadowing
	var ndotl = max(normal.dot(light_dir), 0.0)
	color = color * lerpf(config.micro_shadow, 1.0, ndotl)

	return color.clamp(Color(0, 0, 0), Color(1, 1, 1))

## Style Métal : Specular implicite + anisotropie + faux reflets
static func _compute_metal_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var scale = config.noise_scale

	# Couleur de base métallique
	var color = base

	# Anisotropie procédurale (stries directionnelles)
	var aniso_direction = Vector3(1, 0, 0).normalized()
	var aniso_stripe = sin(position.dot(aniso_direction) * scale * 2.0) * 0.5 + 0.5
	var aniso_variation = aniso_stripe * 0.1 * config.detail
	color = color + Color(aniso_variation, aniso_variation, aniso_variation)

	# Faux reflet (basé sur l'angle de vue simulé)
	var view_dir = Vector3(0, 0, 1).normalized()
	var reflection_angle = normal.dot(view_dir)
	var fake_reflection = pow(1.0 - abs(reflection_angle), 3.0) * 0.3
	color = color + Color(fake_reflection, fake_reflection, fake_reflection * 1.1)

	# Specular implicite
	var specular = compute_specular(position, normal, view_dir, light_dir, MaterialType.METAL, config)
	color = color + Color(specular, specular, specular)

	# Micro-rayures
	var scratch_noise = _fbm(position * scale * 5.0, 2) * 0.05
	color = color + Color(scratch_noise, scratch_noise, scratch_noise)

	return color.clamp(Color(0, 0, 0), Color(1, 1, 1))

## Style Peau : SSS approximatif + noise doux + variation de teinte
static func _compute_skin_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var scale = config.noise_scale

	# Couleur de base peau
	var color = base

	# SSS approximatif (subsurface scattering)
	# Simuler la lumière qui traverse légèrement la surface
	var sss_strength = 0.15 * config.detail
	var sss_color = Color(1.0, 0.6, 0.5)  # Teinte rougeâtre typique SSS
	var ndotl = max(normal.dot(light_dir), 0.0)
	var wrap_ndotl = max((ndotl + 0.5) / 1.5, 0.0)  # Wrapped diffuse
	var sss = lerpf(wrap_ndotl, 1.0, sss_strength) * sss_strength
	color = color * (1.0 - sss) + sss_color * sss

	# Variation de teinte douce (rougeurs, etc.)
	var hue_variation = _fbm(position * scale * 0.3, 3) * 0.1
	color.r = min(color.r + hue_variation, 1.0)
	color.g = min(color.g + hue_variation * 0.5, 1.0)

	# Micro-détails (pores)
	var pore_noise = _worley_noise(position * scale * 3.0) * config.grain * 0.05
	color = color - Color(pore_noise, pore_noise, pore_noise)

	# Éclairage doux
	color = color * lerpf(0.6, 1.0, ndotl)

	return color.clamp(Color(0, 0, 0), Color(1, 1, 1))

## Style Tissu : Noise isotrope + motif
static func _compute_fabric_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var scale = config.noise_scale

	# Tissu avec motif de tissage
	var weave_x = sin(position.x * scale * 4.0) * 0.5 + 0.5
	var weave_y = sin(position.y * scale * 4.0) * 0.5 + 0.5
	var weave = weave_x * weave_y

	# Variation douce
	var soft_variation = _fbm(position * scale * 0.5, 2) * 0.2
	var color = base * (0.8 + weave * 0.2 + soft_variation)

	# Micro-shadowing
	var ndotl = max(normal.dot(light_dir), 0.0)
	color = color * lerpf(config.micro_shadow, 1.0, ndotl)

	return color.clamp(Color(0, 0, 0), Color(1, 1, 1))

## Style Custom : Noise générique
static func _compute_custom_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var scale = config.noise_scale
	var variation = _fbm(position * scale, config.noise_octaves)
	var color = base * (0.7 + variation * 0.6 * config.detail)

	var ndotl = max(normal.dot(light_dir), 0.0)
	color = color * lerpf(config.micro_shadow, 1.0, ndotl)

	return color.clamp(Color(0, 0, 0), Color(1, 1, 1))

static func _compute_glass_color(
	position: Vector3, normal: Vector3, base: Color,
	config: MaterialStyleConfig, light_dir: Vector3
) -> Color:
	var view_dir := Vector3(0, 0, 1)  # Approx: camera looks along +Z
	var ndotv := abs(normal.dot(view_dir))
	var ndotl := max(normal.dot(light_dir), 0.0)

	# Fresnel: edges are more reflective (higher opacity)
	var fresnel: float = 1.0 - ndotv
	fresnel = fresnel * fresnel * fresnel * fresnel  # Schlick quartic approx
	var glass_alpha := clamp(0.15 + fresnel * 0.85, 0.1, 1.0)

	# Specular highlight (Phong-like)
	var reflect_dir: Vector3 = (2.0 * normal * ndotl - light_dir).normalized()
	var spec := pow(max(reflect_dir.dot(view_dir), 0.0), 32.0) * config.specular_strength

	# Base color: transparent tint + specular
	var color := base * (0.2 + spec * 1.5)
	color.a = glass_alpha * config.grain

	# Edge darkening + inner glow
	var edge_glow: float = 1.0 - fresnel * 0.6
	color = Color(color.r * edge_glow, color.g * edge_glow, color.b * edge_glow, glass_alpha)

	return color.clamp(Color(0, 0, 0, 0), Color(1, 1, 1, 1))

# ============================================================================
# FONCTIONS DE NOISE
# ============================================================================

## Simple noise hash
static func _simple_noise(pos: Vector3) -> float:
	var n = sin(pos.x * 12.9898 + pos.y * 78.233 + pos.z * 45.543) * 43758.5453
	return n - floor(n)

## FBM (Fractional Brownian Motion)
static func _fbm(pos: Vector3, octaves: int, lacunarity: float = 2.0, gain: float = 0.5) -> float:
	var value = 0.0
	var amplitude = 1.0
	var frequency = 1.0
	var max_value = 0.0

	for i in range(octaves):
		value += _simple_noise(pos * frequency) * amplitude
		max_value += amplitude
		amplitude *= gain
		frequency *= lacunarity

	return value / max_value

## Worley noise (cellular noise)
static func _worley_noise(pos: Vector3) -> float:
	var cell = Vector3(floor(pos.x), floor(pos.y), floor(pos.z))
	var min_dist = 10.0

	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var neighbor = cell + Vector3(x, y, z)
				var point = neighbor + Vector3(
					_simple_noise(neighbor),
					_simple_noise(neighbor + Vector3(100, 0, 0)),
					_simple_noise(neighbor + Vector3(0, 100, 0))
				)
				var dist = pos.distance_to(point)
				min_dist = min(min_dist, dist)

	return min_dist

## Noise directionnel
static func _directional_noise(pos: Vector3, direction: Vector3, scale: float) -> float:
	var projected = pos.dot(direction) * scale
	return _fbm(Vector3(projected, pos.y * scale, pos.z * scale), 3)
