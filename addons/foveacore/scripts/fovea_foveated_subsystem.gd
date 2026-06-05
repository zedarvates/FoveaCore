class_name FoveaFoveatedSubsystem
extends Node

## FoveaFoveatedSubsystem — Gestion isolée du foveated rendering.
## Extrait de FoveaCoreManager pour respecter le principe de responsabilité unique.
## Responsabilités :
##   - Mise à jour des zones foveated (foveal, parafoveal, périphérique)
##   - Mise à jour du point de regard (eye-tracking ou caméra forward)
##   - Cache des paramètres pour éviter les recalculs inutiles

## Configuration des zones
var foveal_radius: float = 0.15
var foveal_density: float = 2.0
var parafoveal_density: float = 1.0
var peripheral_density: float = 0.3

## Contrôleur sous-jacent (créé en interne)
var _controller: FoveatedController = null

## Cache pour détecter les changements de paramètres
var _cached_radius: float = -1.0
var _cached_foveal: float = -1.0
var _cached_parafoveal: float = -1.0
var _cached_peripheral: float = -1.0
var _dirty: bool = true

func _ready() -> void:
	# S'assurer que les uniforms shader globaux sont déclarés
	var existing = RenderingServer.global_shader_parameter_get_list()
	if not existing.has("fovea_gaze_left"):
		RenderingServer.global_shader_parameter_add("fovea_gaze_left", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0.5, 0.5))
	if not existing.has("fovea_gaze_right"):
		RenderingServer.global_shader_parameter_add("fovea_gaze_right", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0.5, 0.5))

func setup(r: float, foveal: float, parafoveal: float, peripheral: float) -> void:
	foveal_radius = r
	foveal_density = foveal
	parafoveal_density = parafoveal
	peripheral_density = peripheral
	_dirty = true

	_controller = FoveatedController.new()
	_controller.setup_zones(r, foveal, parafoveal, peripheral)
	add_child(_controller)
	print("FoveaFoveatedSubsystem: Zones initialisées. Foveal radius=%.2f" % r)

## Appeler chaque frame — met à jour les zones si les paramètres ont changé
func update(enabled: bool) -> void:
	if not enabled or _controller == null:
		return

	# Reconfigurer si les paramètres ont évolué (dirty check)
	if (_dirty
		or not is_equal_approx(foveal_radius,     _cached_radius)
		or not is_equal_approx(foveal_density,    _cached_foveal)
		or not is_equal_approx(parafoveal_density, _cached_parafoveal)
		or not is_equal_approx(peripheral_density, _cached_peripheral)):

		_controller.setup_zones(foveal_radius, foveal_density, parafoveal_density, peripheral_density)
		_cached_radius      = foveal_radius
		_cached_foveal      = foveal_density
		_cached_parafoveal  = parafoveal_density
		_cached_peripheral  = peripheral_density
		_dirty = false

	# Mise à jour du gaze depuis la caméra si pas d'eye-tracking
	if not _controller.has_eye_tracking():
		var camera := get_viewport().get_camera_3d()
		if camera:
			var forward := -camera.global_transform.basis.z
			var target  := camera.global_transform.origin + forward * 10.0
			_controller.update_gaze(target, forward)

	# Projection 3D -> 2D (écran) du point de regard pour les shaders GPU
	var camera := get_viewport().get_camera_3d()
	if camera:
		var gaze_pt := _controller.get_gaze_point()
		var screen_gaze := Vector2(0.5, 0.5)
		if gaze_pt != Vector3.ZERO:
			var viewport_size := get_viewport().get_visible_rect().size
			if viewport_size.x > 0 and viewport_size.y > 0:
				var unprojected := camera.unproject_position(gaze_pt)
				screen_gaze = unprojected / viewport_size
		
		RenderingServer.global_shader_parameter_set("fovea_gaze_left", screen_gaze)
		RenderingServer.global_shader_parameter_set("fovea_gaze_right", screen_gaze)

## Accès au contrôleur (pour FoveaSplatSubsystem.apply_foveated_pass)
func get_controller() -> FoveatedController:
	return _controller

## Point de regard courant (monde)
func get_gaze_point() -> Vector3:
	if _controller:
		return _controller.get_gaze_point()
	return Vector3.ZERO

## Marquer les paramètres comme modifiés (forcer recalcul)
func mark_dirty() -> void:
	_dirty = true

## Désactiver le foveated : reset le gaze au centre
func disable() -> void:
	if _controller:
		_controller.update_gaze(Vector3.ZERO, Vector3.FORWARD)
