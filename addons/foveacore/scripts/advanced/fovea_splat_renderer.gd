class_name FoveaSplatRenderer
extends MultiMeshInstance3D

## FoveaEngine : Moteur de rendu MultiMesh pour les Gaussian Splats

@export_file("*.fovea") var asset_path: String = ""
@export var cull_threshold: float = 0.0 # 0.0 = Cull tout ce qui dépasse 90 degrés

var culler_pipeline: GPUCullerPipeline
var splat_mesh: QuadMesh

func _ready():
    culler_pipeline = GPUCullerPipeline.new()
    
    # 1. Création de la géométrie de base (Le Quad du Splat)
    splat_mesh = QuadMesh.new()
    splat_mesh.size = Vector2(1.0, 1.0)
    
    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_custom_data = true # Pour stocker la couleur et l'opacité
    multimesh.mesh = splat_mesh
    
    # Attribuer le shader visuel
    var material = ShaderMaterial.new()
    material.shader = load("res://addons/foveacore/shaders/splat_render.gdshader")
    self.material_override = material
    
    if asset_path != "":
        load_and_render_splats()

func load_and_render_splats():
    var camera = get_viewport().get_camera_3d()
    if not camera:
        push_error("FoveaSplatRenderer: No camera in viewport.")
        return
    var cam_pos = camera.global_position

    # Get depth texture from camera if available
    var depth_tex: RID = RID()
    if camera.get_camera_attributes():
        var attrs = camera.get_camera_attributes()
        if attrs.has_method("get_depth_texture"):
            depth_tex = attrs.get_depth_texture()

    # 2. Exécution du Compute Shader ultra-rapide (Culling)
    var output_buffer_rid = culler_pipeline.process_splats_from_file(asset_path, camera, depth_tex, cull_threshold)
    if not output_buffer_rid.is_valid():
        return
        
    # 3. Récupération des données filtrées depuis la VRAM
    var culled_bytes = culler_pipeline.rd.buffer_get_data(output_buffer_rid)
    
    # Chaque splat compressé fait 16 octets (SPLAT_BYTE_SIZE dans le culler)
    var surviving_splats_count = culled_bytes.size() / 16 
    
    multimesh.instance_count = surviving_splats_count
    
    # 4. Décodage et Injection dans le MultiMesh (Phase d'expansion)
    # Dans un pipeline 100% GPU, cette étape serait évitée via un TextureRD.
    # Mais pour la compatibilité avec le Forward+ de Godot, on map les données ici.
    for i in range(surviving_splats_count):
        var offset = i * 16
        # Lecture de la grille quantisée (16 bits)
        var px = culled_bytes.decode_u16(offset) / 65535.0 * 10.0 # Exemple d'échelle locale
        var py = culled_bytes.decode_u16(offset + 2) / 65535.0 * 10.0
        var pz = culled_bytes.decode_u16(offset + 4) / 65535.0 * 10.0
        
        var transform = Transform3D(Basis(), Vector3(px, py, pz))
        multimesh.set_instance_transform(i, transform)
        
        # On injecte l'index de couleur ou l'opacité (Ici on simule un blanc opaque pour la base)
        var opacity = culled_bytes.decode_u8(offset + 12) / 255.0
        multimesh.set_instance_custom_data(i, Color(1.0, 1.0, 1.0, opacity))
        
    print("FoveaEngine: %d splats injectés dans le MultiMesh." % surviving_splats_count)