extends Node
## FoveaCoreManager — Autoload principal pour le moteur FoveaEngine VR.
##
## Rôle : ORCHESTRATEUR LÉGER.
## Ce script ne contient plus de logique métier directe.
## Il instancie et relie les sous-systèmes spécialisés :
##
##   ┌─ FoveaVRSubsystem       — OpenXR, HMD, shaders XR
##   ├─ FoveaFoveatedSubsystem — Zones foveated, eye-tracking, gaze
##   ├─ FoveaSplatSubsystem    — Génération, tri, reprojection, rendu splats
##   └─ (EyeCuller, VisibilityManager, HybridRenderer — nœuds enfants)
##
## API publique préservée pour la compatibilité ascendante :
##   register_splattable(), unregister_splattable(),
##   set_style(), set_splat_density(), toggle_foveated(), toggle_hybrid_mode()

class_name FoveaCoreManagerScript

const _ProxyFaceRendererScript = preload("res://addons/foveacore/scripts/advanced/proxy_face_renderer.gd")

# ─────────────────────────────────────────────────────────────
#  Exports (publics, inspecteur Godot)
# ─────────────────────────────────────────────────────────────

@export_group("VR Settings")
## If [code]true[/code], initializes VR mode using OpenXR. Falls back to desktop mode if unavailable.
@export var vr_enabled := true
## The targeted refresh rate for the VR headset (e.g. 90 Hz, 120 Hz).
@export var target_fps := 90
## If [code]true[/code], enables foveated rendering (varying splat density depending on gaze location).
@export var foveated_enabled := true
## If [code]true[/code], applies custom XR shaders optimized for VR rendering.
@export var xr_shader_enabled := true

@export_group("Splatting Settings")
## Global multiplier for splat rendering density (e.g., 1.0 is default, lower values improve performance).
@export var global_splat_density := 1.0
## The maximum number of splats that can be rendered in a single frame.
@export var max_splats_per_frame := 100000
## The maximum number of dynamic splats rendered simultaneously (performance profile).
@export var max_dynamic_splats := 50000
## The maximum ratio of dynamic splats relative to the total splat count.
@export var max_dynamic_splats_ratio := 0.5
## If [code]true[/code], culls splats that are outside the camera frustum or occluded.
@export var visible_only_culling := true

@export_group("Style Settings")
## The active visual style resource used to render the splats.
@export var active_style: FoveaStyle = null
## The mode used to style splats (e.g. "procedural" or "texture").
@export var style_mode := "procedural"

@export_group("Foveated Settings")
## The angular radius of the fovea (central high-detail region) in radians/meters.
@export var foveal_radius := 0.15
## Density multiplier applied to splats within the foveal (gaze target) area.
@export var foveal_density_multiplier := 2.0
## Density multiplier applied to splats in the transition (parafoveal) zone.
@export var parafoveal_density_multiplier := 1.0
## Density multiplier applied to splats in the peripheral vision zone.
@export var peripheral_density_multiplier := 0.3
## If [code]true[/code], enables multi-layered splatting passes (base, specular, details).
@export var enable_layered_splatting := true

@export_group("Animation Settings")
## If [code]true[/code], enables the Dynamic Splat Animation subsystem (Phase 7).
@export var animation_enabled := true
## Global multiplier applied to all registered animation modifiers.
@export var animation_global_intensity := 1.0

# ─────────────────────────────────────────────────────────────
#  Sous-systèmes (instances gérées en interne)
# ─────────────────────────────────────────────────────────────

## Sous-système OpenXR / VR
var _vr: FoveaVRSubsystem = null

## Sous-système Foveated Rendering
var _foveated: FoveaFoveatedSubsystem = null

## Alias pour la liaison de l'eye-tracking (GazeTrackerLinker)
var _foveated_controller: FoveatedController:
	get:
		return _foveated.get_controller() if _foveated else null

var _layered_foveated_controller: LayeredFoveatedController:
	get:
		return _foveated.get_layered_controller() if _foveated else null

## Sous-système Pipeline Splat (génération → tri → rendu)
var _splat_pipeline: FoveaSplatSubsystem = null

## Sous-système Animation (Phase 7 — offsets additifs non-destructifs)
var _animation: FoveaAnimationSubsystem = null

## Noeuds enfants hérités (Culling, Visibilité, Hybride)
var _eye_culler: EyeCuller = null
var _visibility_manager: VisibilityManager = null
var _hybrid_renderer: HybridRenderer = null
var _occlusion_culler: OcclusionCuller = null
var _temporal_reprojector: TemporalReprojector = null
var _splat_renderer: FoveaCoreSplatRenderer = null
var _splat_sorter: SplatSorter = null

## Dictionnaire des renderers d'instances multiples par chemin d'asset
var _instanced_renderers: Dictionary = {} # String -> FoveaInstancedSplatRenderer

## État global
var renderer_initialized := false
var hybrid_mode_enabled: bool = false
var _frame_count: int = 0

# ─────────────────────────────────────────────────────────────
#  Lifecycle
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_init_culling_nodes()
	_init_subsystems()
	renderer_initialized = true
	print("FoveaCore: Manager initialisé (orchestrateur + 3 sous-systèmes).")
	
	# Task 227: Préréglages Meta Quest 3 / Mobile VR
	var mobile_presets_class = load("res://addons/foveacore/scripts/advanced/fovea_mobile_presets.gd")
	if mobile_presets_class:
		mobile_presets_class.auto_apply_if_mobile_vr(self)

func _init_culling_nodes() -> void:
	## Noeuds de bas niveau (Eye culling, visibilité, occlusion, reprojection, hybride)
	_eye_culler = EyeCuller.new()
	add_child(_eye_culler)

	_visibility_manager = VisibilityManager.new()
	_visibility_manager.setup(_eye_culler)
	add_child(_visibility_manager)

	_temporal_reprojector = TemporalReprojector.new()
	_temporal_reprojector.config.reproject_ratio = 0.7
	add_child(_temporal_reprojector)

	_occlusion_culler = OcclusionCuller.new()
	add_child(_occlusion_culler)

	_hybrid_renderer = HybridRenderer.new()
	add_child(_hybrid_renderer)
	var hybrid_mode := HybridRenderer.RenderMode.HYBRID if hybrid_mode_enabled else HybridRenderer.RenderMode.SPLAT_ONLY
	_hybrid_renderer.set_mode(hybrid_mode)

	_splat_renderer = FoveaCoreSplatRenderer.new()
	_splat_renderer.name = "FoveaCoreSplatRenderer"
	add_child(_splat_renderer)

	_splat_sorter = SplatSorter.new()

func _init_subsystems() -> void:
	## 1. Sous-système VR
	_vr = FoveaVRSubsystem.new()
	add_child(_vr)
	_vr.xr_unavailable.connect(_on_xr_unavailable)
	_vr.setup(vr_enabled, xr_shader_enabled)

	## 2. Sous-système Foveated
	_foveated = FoveaFoveatedSubsystem.new()
	add_child(_foveated)
	_foveated.setup(
		foveal_radius,
		foveal_density_multiplier,
		parafoveal_density_multiplier,
		peripheral_density_multiplier
	)

	## 3. Sous-système Animation (doit exister avant le pipeline splat pour l'injection)
	_animation = FoveaAnimationSubsystem.new()
	_animation.name = "FoveaAnimationSubsystem"
	_animation.enabled = animation_enabled
	_animation.global_intensity = animation_global_intensity
	add_child(_animation)

	## 4. Pipeline Splat
	_splat_pipeline = FoveaSplatSubsystem.new()
	add_child(_splat_pipeline)
	_splat_pipeline.setup(global_splat_density, max_splats_per_frame)
	# Injecter les dépendances
	_splat_pipeline.temporal_reprojector = _temporal_reprojector
	_splat_pipeline.occlusion_culler     = _occlusion_culler
	_splat_pipeline.splat_sorter         = _splat_sorter
	_splat_pipeline.splat_renderer       = _splat_renderer
	_splat_pipeline.animation_subsystem  = _animation

# ─────────────────────────────────────────────────────────────
#  Loop principale — orchestre les sous-systèmes
# ─────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not renderer_initialized:
		return
	_frame_count += 1

	# Délégation aux sous-systèmes
	_foveated.update(foveated_enabled)
	_run_culling_pass()

func _run_culling_pass() -> void:
	if _visibility_manager == null:
		return

	var camera := get_viewport().get_camera_3d()
	var camera_pos := _get_main_camera_position()

	# Dynamically update eye culling camera and frustums
	if camera and _eye_culler and _visibility_manager:
		var left_proj := camera.get_camera_projection()
		var right_proj := camera.get_camera_projection()
		var left_trans := camera.global_transform
		var right_trans := camera.global_transform
		
		if _vr and _vr.is_xr_active:
			var xr_interface: XRInterface = XRServer.primary_interface
			if xr_interface:
				left_trans = xr_interface.get_transform_for_view(0, camera.global_transform)
				right_trans = xr_interface.get_transform_for_view(1, camera.global_transform)
				var aspect := 1.0
				var vp := camera.get_viewport()
				if vp:
					aspect = float(vp.size.x) / float(max(1, vp.size.y))
				left_proj = xr_interface.get_projection_for_view(0, aspect, camera.near, camera.far)
				right_proj = xr_interface.get_projection_for_view(1, aspect, camera.near, camera.far)
				
		_eye_culler.update_frustums(left_proj, left_trans, right_proj, right_trans)
		_visibility_manager.update_camera_positions(left_trans.origin, left_trans, right_trans.origin, right_trans)

	# Feed viewport texture to build Hi-Z depth pyramid for occlusion culling (Task 3)
	# NOTE: Viewport image readback causes GPU stall, so it is disabled by default for performance.
	# GPU-side culling is handled natively via FoveaCompositorEffect.
	# if _occlusion_culler and visible_only_culling and DisplayServer.get_name() != "headless":
	# 	var vp := get_viewport()
	# 	if vp:
	# 		var vp_tex := vp.get_texture()
	# 		if vp_tex:
	# 			var img := vp_tex.get_image()
	# 			if img:
	# 				_occlusion_culler.build_hi_z_pyramid(img)

	# Skip culling pass if we are in MESH_ONLY mode to save CPU cycles
	if _hybrid_renderer and _hybrid_renderer.current_mode == HybridRenderer.RenderMode.MESH_ONLY:
		return

	var visibility_result: VisibilityManager.FrameVisibilityResult = _visibility_manager.extract_visible_surfaces()

	# Hybrid setup (optionnel)
	if _hybrid_renderer:
		for node in visibility_result.per_node_results:
			if node is FoveaSplattable and node._mesh_instance_ref != null:
				_hybrid_renderer.setup_for_node(node._mesh_instance_ref, _splat_renderer)

	# Génération + tri via le sous-système splat
	_splat_pipeline.process_frame(visibility_result, camera, camera_pos)

	# Passe foveated (filtrage par densité + minimize_overdraw)
	if foveated_enabled:
		_splat_pipeline.apply_foveated_pass(_foveated.get_controller(), _layered_foveated_controller, enable_layered_splatting)

	if _frame_count % 60 == 0:
		print("FoveaCore: %d splats rendus ce frame." % _splat_pipeline.current_splats.size())

# ─────────────────────────────────────────────────────────────
#  API publique (compatibilité ascendante garantie)
# ─────────────────────────────────────────────────────────────

## Registers a [FoveaSplattable] node into the culling, LOD, and global instancing system.
## Handles automatic attachment of proxy Level of Detail (LOD) nodes and manages instanced renderers for [code].fovea[/code] assets.
func register_splattable(node: FoveaSplattable) -> void:
	if _eye_culler:
		_eye_culler.register_splattable(node)
	if _visibility_manager:
		_visibility_manager.register_splattable(node)
	
	# Gestion de l'instanciation globale pour les fichiers .fovea
	if node.splat_file_path.ends_with(".fovea") and node.enable_instancing:
		var path := node.splat_file_path
		if not _instanced_renderers.has(path):
			var instanced_renderer: FoveaInstancedSplatRenderer = FoveaInstancedSplatRenderer.new()
			instanced_renderer.name = "InstancedRenderer_" + path.get_file().get_basename()
			instanced_renderer.asset_path = path
			instanced_renderer.sort_distance_threshold = 0.1
			add_child(instanced_renderer)
			_instanced_renderers[path] = instanced_renderer
			print("FoveaCoreManager: Création du FoveaInstancedSplatRenderer pour '%s'" % path.get_file())
	
	# Attacher un LOD proxy pour les grandes distances (seulement pour le mode non-instancié)
	if not node.enable_instancing:
		var proxy := _ProxyFaceRendererScript.new()
		proxy.name = "ProxyFace_" + node.name
		proxy.target_splattable = node
		proxy.switch_distance = 30.0
		node.add_child(proxy)

## Unregisters a [FoveaSplattable] node from the culling and visibility systems.
## Cleans up any attached LOD proxy nodes or unused instanced renderers.
func unregister_splattable(node: FoveaSplattable) -> void:
	if _eye_culler:
		_eye_culler.unregister_splattable(node)
	if _visibility_manager:
		_visibility_manager.unregister_splattable(node)
	
	if not node.enable_instancing:
		for child in node.get_children():
			if child.get_script() == _ProxyFaceRendererScript:
				child.queue_free()
	else:
		call_deferred("_check_and_cleanup_unused_instanced_renderers")

func _check_and_cleanup_unused_instanced_renderers() -> void:
	var active_nodes: Array[Node] = get_tree().get_nodes_in_group("splattables")
	var active_paths: Array[String] = []
	for n in active_nodes:
		if n is FoveaSplattable and n.enable_instancing and n.splat_file_path.ends_with(".fovea"):
			if not active_paths.has(n.splat_file_path):
				active_paths.append(n.splat_file_path)
	
	var paths_to_remove: Array[String] = []
	for path: String in _instanced_renderers:
		if not active_paths.has(path):
			paths_to_remove.append(path)

	for path: String in paths_to_remove:
		var renderer: FoveaInstancedSplatRenderer = _instanced_renderers[path]
		if is_instance_valid(renderer):
			renderer.queue_free()
		_instanced_renderers.erase(path)
		print("FoveaCoreManager: Libération du FoveaInstancedSplatRenderer inutilisé pour '%s'" % path.get_file())

## Changes the global rendering style to the specified [FoveaStyle] resource.
func set_style(style: FoveaStyle) -> void:
	active_style = style
	print("FoveaCore style changed: ", style.mode)

## Modifies the global splat density multiplier.
## Clamps the value between [code]0.1[/code] (lowest density) and [code]5.0[/code] (highest density).
func set_splat_density(density: float) -> void:
	global_splat_density = clamp(density, 0.1, 5.0)
	_splat_pipeline.global_splat_density = global_splat_density
	if _foveated:
		_foveated.mark_dirty()

## Dynamically activates or deactivates foveated rendering at runtime.
func toggle_foveated(enabled: bool) -> void:
	foveated_enabled = enabled
	if _foveated:
		_foveated.mark_dirty()
		if not enabled:
			_foveated.disable()

## Dynamically activates or deactivates the Dynamic Splat Animation subsystem at runtime.
func toggle_animation(enabled: bool) -> void:
	animation_enabled = enabled
	if _animation:
		_animation.enabled = enabled

## Returns the [FoveaAnimationSubsystem] instance so animator nodes (flow fields,
## covariance morphing, etc.) can register their modifiers.
func get_animation_subsystem() -> FoveaAnimationSubsystem:
	return _animation

## Toggles the hybrid rendering mode between combined mesh + splat rendering and splat-only rendering.
func toggle_hybrid_mode() -> void:
	hybrid_mode_enabled = not hybrid_mode_enabled
	if _hybrid_renderer:
		var mode := HybridRenderer.RenderMode.HYBRID if hybrid_mode_enabled else HybridRenderer.RenderMode.SPLAT_ONLY
		_hybrid_renderer.set_mode(mode)
		print("FoveaCore: Hybrid mode %s." % ("enabled" if hybrid_mode_enabled else "disabled"))

# ─────────────────────────────────────────────────────────────
#  Helpers internes
# ─────────────────────────────────────────────────────────────

func _get_main_camera_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera else Vector3.ZERO

func _on_xr_unavailable(reason: String) -> void:
	print("FoveaCoreManager: OpenXR non disponible (%s). Repli sur le mode Desktop." % reason)
	vr_enabled = false
	foveated_enabled = false
	if _foveated:
		_foveated.disable()

func _exit_tree() -> void:
	if _splat_sorter:
		_splat_sorter._cleanup_gpu()
