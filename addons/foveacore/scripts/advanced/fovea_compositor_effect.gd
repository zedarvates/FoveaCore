class_name FoveaCompositorEffect
extends CompositorEffect

## FoveaEngine : Intercepteur de pipeline pour l'Occlusion Culling (Hi-Z)

var culler_pipeline: GPUCullerPipeline
var target_camera: Camera3D
var fovea_asset_path: String

func _init():
    # On s'insère JUSTE APRÈS la passe opaque de Godot.
    # À ce moment précis, le Depth Buffer contient la profondeur de tous les murs/décors.
    effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE
    culler_pipeline = GPUCullerPipeline.new()

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
    
    # 3. Exécution de notre Compute Shader avec la caméra et la depth map
    var output_buffer_rid = culler_pipeline.process_splats_from_file(
        fovea_asset_path, 
        target_camera, 
        depth_texture_rid, 
        0.0
    )
    
    # Note : Dans une architecture 100% GPU, c'est ici que l'on déclencherait 
    # également le draw call du MultiMesh via un `draw_list` personnalisé,
    # au lieu de repasser les données au thread principal.

func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        if culler_pipeline:
            culler_pipeline.cleanup()