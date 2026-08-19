class_name FoveaCompositorEffect
extends CompositorEffect

## FoveaEngine : Intercepteur de pipeline pour l'Occlusion Culling (Hi-Z) et la Rasterisation par tuiles

var culler_pipeline: GPUCullerPipeline
var target_camera: Camera3D
var fovea_asset_path: String
var target_renderer: FoveaCoreSplatRenderer = null
var cached_hlod_distances: Array = [8.0, 18.0, 30.0]
var enable_tile_rasterizer: bool = false

func _init(pipeline: GPUCullerPipeline = null) -> void:
	# On s'insère JUSTE APRÈS la passe opaque de Godot.
	# À ce moment précis, le Depth Buffer contient la profondeur de tous les murs/décors.
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE
	culler_pipeline = pipeline if pipeline != null else GPUCullerPipeline.new()

## Exécuté sur le Thread de Rendu (Rendering Thread) par le moteur Godot
func _render_callback(effect_callback_type: int, render_data: RenderData):
	if not target_camera or fovea_asset_path.is_empty():
		return
		
	# 1. Récupération des buffers internes de Godot
	var render_scene_buffers = render_data.get_render_scene_buffers()
	if not render_scene_buffers:
		return
		
	# 2. On extrait le RID de la Texture de Profondeur (Depth Map) !
	var depth_texture_rid = render_scene_buffers.get_depth_texture()
	
	# Récupérer RenderSceneData pour avoir les vraies matrices stéréoscopiques
	var render_scene_data = render_data.get_render_scene_data()
	
	# 3. Exécution de notre Compute Shader avec la caméra et la depth map
	culler_pipeline.skip_sync = enable_tile_rasterizer
	var output_buffer_rid = culler_pipeline.process_splats_from_file(
		fovea_asset_path, 
		target_camera, 
		depth_texture_rid, 
		0.0,
		culler_pipeline.last_aabb_min,
		culler_pipeline.last_aabb_max,
		render_scene_data,
		cached_hlod_distances,
		culler_pipeline.last_covar_texture_rid,
		culler_pipeline.last_palette_texture_rid,
		culler_pipeline.last_use_palette,
		culler_pipeline.last_palette_size,
		culler_pipeline.last_model_transform
	)
	
	# 4. Rasterisation par tuiles d'écran (16x16) directe sur le Viewport Color Buffer
	if enable_tile_rasterizer and output_buffer_rid.is_valid():
		var color_texture_rid = render_scene_buffers.get_color_texture()
		if color_texture_rid.is_valid():
			culler_pipeline.dispatch_tile_based_rasterization_cached(target_camera, color_texture_rid)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if culler_pipeline:
			culler_pipeline.cleanup()
