extends Node
## FoveaCoreManager - Autoload principal pour le moteur VR
## Gère le rendu stéréo, le foveated rendering, et le Style Engine

class_name FoveaCoreManagerScript

## Configuration VR
@export_group("VR Settings")
@export var vr_enabled := true
@export var target_fps := 90
@export var foveated_enabled := true
@export var xr_shader_enabled := true

## Configuration Splatting
@export_group("Splatting Settings")
@export var global_splat_density := 1.0
@export var max_splats_per_frame := 100000
@export var visible_only_culling := true

## Configuration Style
@export_group("Style Settings")
@export var active_style: FoveaStyle = null
@export var style_mode := "procedural" # "procedural" ou "neural"

## Configuration Foveated Rendering
@export_group("Foveated Settings")
@export var foveal_radius := 0.15 # radians
@export var foveal_density_multiplier := 2.0
@export var parafoveal_density_multiplier := 1.0
@export var peripheral_density_multiplier := 0.3

## État du renderer
var renderer_initialized := false
var current_eye_transforms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]

## Eye culler pour le frustum culling par œil
var _eye_culler: EyeCuller = null

## Visibility manager pour l'extraction de surfaces visibles
var _visibility_manager: VisibilityManager = null

## Configuration du générateur de splats
var _splat_config: SplatGenerator.SplatConfig = null

## Contrôleur foveated
var _foveated_controller: FoveatedController = null

## Renderer de splats
var _splat_renderer: SplatRenderer = null

## Splats générés pour le frame courant
var _current_splats: Array[GaussianSplat] = []

## Temporal reprojector pour la cohérence temporelle
var _temporal_reprojector: TemporalReprojector = null

## Position précédente de la caméra pour la reprojection
var _previous_camera_position: Vector3 = Vector3.ZERO

## Hybrid renderer
var _hybrid_renderer: HybridRenderer = null
var hybrid_mode_enabled: bool = false

## Occlusion culler for Hi-Z buffer occlusion testing
var _occlusion_culler: OcclusionCuller = null

var _frame_count: int = 0

var _foveated_params_dirty := true
var _cached_foveal_radius := 0.0
var _cached_foveal_density := 0.0
var _cached_parafoveal_density := 0.0
var _cached_peripheral_density := 0.0

func _ready():
	_initialize_renderer()
	_setup_vr()

func _initialize_renderer():
	_eye_culler = EyeCuller.new()
	add_child(_eye_culler)

	_visibility_manager = VisibilityManager.new()
	_visibility_manager.setup(_eye_culler)
	add_child(_visibility_manager)

	# Configuration du générateur de splats
	_splat_config = SplatGenerator.SplatConfig.new()
	_splat_config.splats_per_triangle = 3
	_splat_config.min_radius = 0.02
	_splat_config.max_radius = 0.3
	_splat_config.depth_aware_blending = true

	# Contrôleur foveated
	_foveated_controller = FoveatedController.new()
	_foveated_controller.setup_zones(
		foveal_radius,
		foveal_density_multiplier,
		parafoveal_density_multiplier,
		peripheral_density_multiplier
	)
	add_child(_foveated_controller)

	# Renderer de splats
	_splat_renderer = SplatRenderer.new()
	add_child(_splat_renderer)

	# Temporal reprojector
	_temporal_reprojector = TemporalReprojector.new()
	_temporal_reprojector.config.reproject_ratio = 0.7
	add_child(_temporal_reprojector)

	# Hybrid renderer
	_hybrid_renderer = HybridRenderer.new()
	add_child(_hybrid_renderer)

	# Occlusion culler for Hi-Z buffer occlusion testing
	_occlusion_culler = OcclusionCuller.new()
	add_child(_occlusion_culler)

	renderer_initialized = true
	print("FoveaCore renderer initialized with hybrid mesh-splat support")

func _setup_vr():
	if vr_enabled:
		print("FoveaCore: Enabling OpenXR 1.0+ Integration...")
		# Find OpenXR Interface
		var xr_interface = XRServer.find_interface("OpenXR")
		if xr_interface:
			if not xr_interface.is_initialized():
				if xr_interface.initialize():
					get_viewport().use_xr = true
					ProjectSettings.set_setting("xr/shaders/enabled", xr_shader_enabled)
					print("FoveaCore: OpenXR interface initialized. XR Shader: ", xr_shader_enabled)
				else:
					push_warning("FoveaCore: Failed to initialize OpenXR.")
			else:
				get_viewport().use_xr = true
				ProjectSettings.set_setting("xr/shaders/enabled", xr_shader_enabled)
				print("FoveaCore: OpenXR already active. XR Shader: ", xr_shader_enabled)
		else:
			push_warning("FoveaCore: No OpenXR interface found.")

func _process(delta):
	if vr_enabled and renderer_initialized:
		_frame_count += 1
		_update_foveated_zones()
		_perform_culling()

func _update_foveated_zones():
	if foveated_enabled and _foveated_controller:
		if (_foveated_params_dirty or
			not is_equal_approx(foveal_radius, _cached_foveal_radius) or
			not is_equal_approx(foveal_density_multiplier, _cached_foveal_density) or
			not is_equal_approx(parafoveal_density_multiplier, _cached_parafoveal_density) or
			not is_equal_approx(peripheral_density_multiplier, _cached_peripheral_density)):
			_foveated_params_dirty = false
			_cached_foveal_radius = foveal_radius
			_cached_foveal_density = foveal_density_multiplier
			_cached_parafoveal_density = parafoveal_density_multiplier
			_cached_peripheral_density = peripheral_density_multiplier
			_foveated_controller.setup_zones(
				foveal_radius,
				foveal_density_multiplier,
				parafoveal_density_multiplier,
				peripheral_density_multiplier
			)

		if not _foveated_controller.has_eye_tracking():
			var camera = get_viewport().get_camera_3d()
			if camera:
				var forward = -camera.global_transform.basis.z
				var target = camera.global_transform.origin + forward * 10.0
				_foveated_controller.update_gaze(target, forward)

func _perform_culling():
	if _visibility_manager and foveated_enabled:
		var visibility_result = _visibility_manager.extract_visible_surfaces()
		var camera = get_viewport().get_camera_3d()
		var camera_pos: Vector3 = _get_main_camera_position()

		_do_hybrid_setup(visibility_result, camera)
		_do_generate_and_filter(visibility_result, camera, camera_pos)
		_do_foveated_pass(camera_pos)
		_do_gpu_render()

		_previous_camera_position = camera_pos


func _do_hybrid_setup(visibility_result, camera: Camera3D):
	if hybrid_mode_enabled and _hybrid_renderer:
		for node in visibility_result.per_node_results:
			if node is MeshInstance3D:
				_hybrid_renderer.setup_for_node(node, _splat_renderer)


func _do_generate_and_filter(visibility_result, camera: Camera3D, camera_pos: Vector3):
	if _temporal_reprojector:
		_current_splats = []
		for node in visibility_result.per_node_results:
			var extraction = visibility_result.per_node_results[node]
			var filtered_triangles = _filter_triangles_via_occlusion(extraction.visible_triangles, camera)
			var reprojected: Array[GaussianSplat] = _temporal_reprojector.reproject_splats(
				node,
				[],
				camera_pos,
				_previous_camera_position,
				filtered_triangles
			)
			_current_splats.append_array(reprojected)
	else:
		_current_splats = SplatGenerator.generate_all_splats(
			visibility_result,
			camera_pos,
			_splat_config,
			global_splat_density
		)

	_current_splats = SplatSorter.sort_by_depth(_current_splats, camera_pos)


func _filter_triangles_via_occlusion(triangles: Array, camera: Camera3D) -> Array:
	if _occlusion_culler and camera:
		var view_proj = camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse())
		var filtered: Array = []
		for tri in triangles:
			if not _occlusion_culler.is_occluded(tri.center, view_proj, camera.global_transform):
				filtered.append(tri)
		return filtered
	return triangles


func _do_foveated_pass(camera_pos: Vector3):
	if foveated_enabled and _foveated_controller:
		var gaze_point: Vector3 = _foveated_controller.get_gaze_point()
		var foveated_splats: Array[GaussianSplat] = []

		for splat in _current_splats:
			var weight: float = _foveated_controller.get_foveal_weight(splat.position)
			var density: float = _foveated_controller.get_density_multiplier(splat.position)

			splat.apply_foveal_weight(weight * density / 2.0)

			if splat.opacity > 0.05:
				foveated_splats.append(splat)

		_current_splats = foveated_splats

	_current_splats = SplatSorter.minimize_overdraw(_current_splats)


func _do_gpu_render():
	if _splat_renderer:
		var rendered: int = _splat_renderer.render_splats(_current_splats)
		if _frame_count % 60 == 0:
			print("FoveaCore: Rendering %d splats (%d before culling)" % [rendered, _current_splats.size()])

## API publique
func register_splattable(node: FoveaSplattable):
	if _eye_culler:
		_eye_culler.register_splattable(node)
	if _visibility_manager:
		_visibility_manager.register_splattable(node)

func unregister_splattable(node: FoveaSplattable):
	if _eye_culler:
		_eye_culler.unregister_splattable(node)
	if _visibility_manager:
		_visibility_manager.unregister_splattable(node)

func set_style(style: FoveaStyle):
	active_style = style
	print("FoveaCore style changed: ", style.mode)

func set_splat_density(density: float):
	global_splat_density = clamp(density, 0.1, 5.0)
	_foveated_params_dirty = true

func toggle_foveated(enabled: bool):
	foveated_enabled = enabled
	_foveated_params_dirty = true
	if _foveated_controller:
		# Si désactivé, utiliser le point de regard par défaut (centre)
		if not enabled:
			_foveated_controller.update_gaze(Vector3.ZERO, Vector3.FORWARD)


## Obtenir la position de la caméra principale
func _get_main_camera_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		return camera.global_position
	return Vector3.ZERO


## Obtenir le point de regard (eye-tracking si disponible)
func _get_gaze_point() -> Vector3:
	if _foveated_controller:
		return _foveated_controller.get_gaze_point()
	return Vector3.ZERO


## Toggle hybrid mode
func toggle_hybrid_mode():
	hybrid_mode_enabled = not hybrid_mode_enabled
	if hybrid_mode_enabled and _hybrid_renderer:
		_hybrid_renderer.set_mode(HybridRenderer.RenderMode.HYBRID)
		print("Hybrid mode enabled")
	elif _hybrid_renderer:
		_hybrid_renderer.set_mode(HybridRenderer.RenderMode.SPLAT_ONLY)
		print("Hybrid mode disabled (splat only)")
