class_name FoveaSplatRenderer
extends MultiMeshInstance3D

## FoveaEngine : Moteur de rendu MultiMesh pour les Gaussian Splats
## VERSION TRIANGLE - Utilise un maillage triangulaire au lieu de quads
## Optimisation : réduction drastique du coût du fragment shader

@export_file("*.fovea") var asset_path: String = ""
@export var cull_threshold: float = 0.0 # 0.0 = Cull tout ce qui dépasse 90 degrés
@export var use_triangle_mesh: bool = true  # Utiliser le maillage triangle optimisé
@export var splat_subdivisions: int = 16    # Nombre de segments pour l'ellipse

var culler_pipeline: GPUCullerPipeline
var splat_mesh: ArrayMesh
var triangle_mesh_generator

func _ready():
    culler_pipeline = GPUCullerPipeline.new()
    
    # Charger le générateur de maillage triangle
    triangle_mesh_generator = load("res://addons/foveacore/scripts/advanced/triangle_splat_mesh.gd")
    
    # 1. Création de la géométrie de base (Maillage TRIANGLE)
    if use_triangle_mesh:
        splat_mesh = triangle_mesh_generator.generate_triangle_splat_mesh_optimized()
    else:
        # Fallback: QuadMesh classique (ancienne méthode)
        var quad_mesh = QuadMesh.new()
        quad_mesh.size = Vector2(1.0, 1.0)
        # Convertir le quad en ArrayMesh pour compatibilité
        var st = SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        st.add_vertex(Vector3(-0.5, -0.5, 0))
        st.add_vertex(Vector3(0.5, -0.5, 0))
        st.add_vertex(Vector3(0.5, 0.5, 0))
        st.add_vertex(Vector3(-0.5, -0.5, 0))
        st.add_vertex(Vector3(0.5, 0.5, 0))
        st.add_vertex(Vector3(-0.5, 0.5, 0))
        splat_mesh = st.commit()
    
    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_custom_data = true # Pour stocker la couleur et l'opacité
    multimesh.mesh = splat_mesh
    
    # Attribuer le shader triangle optimisé
    var material = ShaderMaterial.new()
    material.shader = load("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
    material.set_shader_parameter("splat_subdivisions", splat_subdivisions)
    material.set_shader_parameter("use_palette", false)
    material.set_shader_parameter("palette_size", 0)
    self.material_override = material

    if asset_path != "":
        load_and_render_splats()

## Configure le rendu avec une palette de couleurs (Digital Painting style)
func setup_palette(palette: FoveaColorPalette) -> void:
    if palette == null or palette.colors.is_empty():
        return

    var material := material_override as ShaderMaterial
    if material == null:
        return

    var data: PackedByteArray = palette.to_packed_rgb_array()
    var img := Image.create_from_data(1, palette.colors.size(), false, Image.FORMAT_RGBA8, data)
    var tex := ImageTexture.create_from_image(img)
    tex.filter_clip = true  # Nearest filtering for palette lookup

    material.set_shader_parameter("use_palette", true)
    material.set_shader_parameter("palette_texture", tex)
    material.set_shader_parameter("palette_size", palette.colors.size())
    print("FoveaSplatRenderer: Palette '%s' (%d colors) applied to shader." % \
          [palette.palette_name, palette.colors.size()])

## Load palette from .fovea file and apply to material
func load_palette_from_fovea() -> void:
    if not ClassDB.can_instantiate("FoveaAssetLoader"):
        push_warning("FoveaSplatRenderer: FoveaAssetLoader GDExtension not available for palette.")
        return

    var loader := ClassDB.instantiate("FoveaAssetLoader")
    if not loader or not loader.has_method("load_color_codebook"):
        return

    var palette_bytes: PackedByteArray = loader.load_color_codebook(asset_path)
    if palette_bytes.is_empty():
        return

    var palette_colors := palette_bytes.size() / 4
    if palette_colors == 0:
        return

    # Create palette resource from raw bytes
    var palette := FoveaColorPalette.new()
    palette.palette_name = asset_path.get_file() + " palette"
    palette.palette_size = palette_colors
    palette.colors.resize(palette_colors)
    for i in palette_colors:
        var r := float(palette_bytes[i * 4]) / 255.0
        var g := float(palette_bytes[i * 4 + 1]) / 255.0
        var b := float(palette_bytes[i * 4 + 2]) / 255.0
        palette.colors[i] = Color(r, g, b)

    setup_palette(palette)

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
    
    # 2. Récupérer l'AABB depuis le fichier .fovea si possible
    var aabb_min := Vector3(-5, -5, -5)
    var aabb_max := Vector3(5, 5, 5)
    if ClassDB.can_instantiate("FoveaAssetLoader"):
        var loader = ClassDB.instantiate("FoveaAssetLoader")
        if loader and loader.has_method("get_asset_aabb"):
            var aabb: AABB = loader.get_asset_aabb(asset_path)
            if aabb.size.length_squared() > 0.001:
                aabb_min = aabb.position
                aabb_max = aabb.end

    # 3. Exécution du Compute Shader ultra-rapide (Culling)
    var output_buffer_rid = culler_pipeline.process_splats_from_file(
        asset_path, camera, depth_tex, cull_threshold, aabb_min, aabb_max)
    if not output_buffer_rid.is_valid():
        return
        
    # 3. Récupération des données filtrées depuis la VRAM
    if culler_pipeline == null or culler_pipeline.rd == null:
        push_error("FoveaSplatRenderer: culler_pipeline or rd is null, skipping data readback.")
        return
    var culled_bytes = culler_pipeline.rd.buffer_get_data(output_buffer_rid)
    
    # Chaque splat compressé fait 16 octets (SPLAT_BYTE_SIZE dans le culler)
    var surviving_splats_count = culled_bytes.size() / 16 
    
    multimesh.instance_count = surviving_splats_count
    
    # 4. Décodage et Injection dans le MultiMesh
    # On utilise les custom_data pour passer les paramètres au shader
    for i in range(surviving_splats_count):
        var offset = i * 16
        # Lecture de la grille quantisée (16 bits)
        var px = culled_bytes.decode_u16(offset) / 65535.0 * 10.0
        var py = culled_bytes.decode_u16(offset + 2) / 65535.0 * 10.0
        var pz = culled_bytes.decode_u16(offset + 4) / 65535.0 * 10.0
        
        var transform = Transform3D(Basis(), Vector3(px, py, pz))
        multimesh.set_instance_transform(i, transform)
        
        # On injecte l'index de couleur et l'opacité dans custom_data
        var color_index = culled_bytes.decode_u16(offset + 8)  # data2 low word
        var covar_index = culled_bytes.decode_u16(offset + 10) # data2 high word
        var opacity = culled_bytes.decode_u8(offset + 12) / 255.0
        
        # Stockage dans custom_data (RGBA format)
        # R,G = position quantifiée (pour décodage shader si besoin)
        # B = opacity
        # A = unused
        multimesh.set_instance_custom_data(i, Color(
            float(color_index) / 65535.0,
            float(covar_index) / 65535.0,
            opacity,
            1.0
        ))
    
    print("FoveaEngine: %d splats injectés dans le MultiMesh (mode TRIANGLE)." % surviving_splats_count)
    
    # Libération du buffer GPU
    culler_pipeline.rd.free_rid(output_buffer_rid)

## Méthode pour mettre à jour dynamiquement le maillage
func update_splat_mesh_mode(use_triangle: bool):
    use_triangle_mesh = use_triangle
    if use_triangle:
        splat_mesh = triangle_mesh_generator.generate_triangle_splat_mesh_optimized()
    else:
        var quad_mesh = QuadMesh.new()
        quad_mesh.size = Vector2(1.0, 1.0)
        var st = SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        st.add_vertex(Vector3(-0.5, -0.5, 0))
        st.add_vertex(Vector3(0.5, -0.5, 0))
        st.add_vertex(Vector3(0.5, 0.5, 0))
        st.add_vertex(Vector3(-0.5, -0.5, 0))
        st.add_vertex(Vector3(0.5, 0.5, 0))
        st.add_vertex(Vector3(-0.5, 0.5, 0))
        splat_mesh = st.commit()
    
    multimesh.mesh = splat_mesh
    material_override.set_shader_parameter("splat_subdivisions", splat_subdivisions)