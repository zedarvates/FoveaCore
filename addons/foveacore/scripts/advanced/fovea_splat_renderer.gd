class_name FoveaSplatRenderer
extends MultiMeshInstance3D

## FoveaEngine : Moteur de rendu MultiMesh pour les Gaussian Splats
## VERSION TRIANGLE - Utilise un maillage triangulaire au lieu de quads
## Optimisation : réduction drastique du coût du fragment shader

@export_file("*.fovea") var asset_path: String = ""
@export var cull_threshold: float = 0.0 # 0.0 = Cull tout ce qui dépasse 90 degrés
@export var use_triangle_mesh: bool = true  # Utiliser le maillage triangle optimisé
@export var splat_subdivisions: int = 16    # Nombre de segments pour l'ellipse

@export_group("Cleaning (FoveaSplatCleaner)")
## Activer le filtrage des floaters et NaN après le GPU culling (P3 intégration cleaner)
@export var enable_cleaning: bool = true
## Radius de voisinage pour la détection des floaters (cellules voxel)
@export_range(1, 4) var floater_neighbor_radius: int = 1
## Nombre minimum de voisins pour qu'un splat soit conservé
@export_range(1, 10) var floater_min_neighbors: int = 2
## Décimer le nuage de points après le nettoyage
@export var enable_decimation: bool = false
## Cible après décimation (0 = désactivé)
@export var decimation_target: int = 50000

var culler_pipeline: GPUCullerPipeline
var splat_mesh: ArrayMesh
var triangle_mesh_generator

## Référence optionnelle au FoveaClayDeformer attaché à ce renderer.
## Peut être assigné manuellement ou automatiquement par le deformer lui-même.
var deformer: FoveaClayDeformer = null

## Cache des transforms originaux (état de repos), alimenté après chaque load.
## Partagé avec le deformer pour un accès non-destructif.
var _original_transforms: Array[Transform3D] = []

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

func _process(_delta: float) -> void:
    var camera := get_viewport().get_camera_3d()
    if camera == null or material_override == null:
        return

    var dist := global_position.distance_to(camera.global_position)

    # Calcul dynamique du ratio LOD stochastique selon la distance
    var lod := 1.0
    if dist > 25.0:
        lod = 0.15   # Rend seulement 15% des splats au loin
    elif dist > 15.0:
        lod = 0.40   # Rend 40% à moyenne distance
    elif dist > 8.0:
        lod = 0.75   # Rend 75% de près

    var mat := material_override as ShaderMaterial
    if mat:
        mat.set_shader_parameter("lod_ratio", lod)

    # Passe de déformation Clay (non-destructif : opère sur les originaux)
    if deformer and deformer.enabled and multimesh and multimesh.instance_count > 0:
        deformer.deform_multimesh(multimesh)

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
    var surviving_splats_count := culled_bytes.size() / 16
    print("FoveaEngine: %d splats GPU après culling." % surviving_splats_count)

    # 4b. Passe de nettoyage optionnelle (FoveaSplatCleaner — P3)
    # Opère sur les bytes bruts AVANT décodage : pas de coût supplémentaire d'allocation.
    if enable_cleaning and surviving_splats_count > 0:
        var before_clean := surviving_splats_count
        # Filtre NaN/outliers (splats quantisés à (65535,65535,65535))
        culled_bytes = FoveaSplatCleaner.filter_nan_inf(culled_bytes)
        # Filtre des floaters isolés dans l'espace voxel
        culled_bytes = FoveaSplatCleaner.filter_floaters(
            culled_bytes, floater_neighbor_radius, floater_min_neighbors)
        # Décimation optionnelle
        if enable_decimation and decimation_target > 0:
            culled_bytes = FoveaSplatCleaner.decimate(culled_bytes, decimation_target)
        surviving_splats_count = culled_bytes.size() / 16
        if before_clean != surviving_splats_count:
            print("FoveaEngine: SplatCleaner: %d → %d splats (-%d)." % [
                before_clean, surviving_splats_count, before_clean - surviving_splats_count])

    multimesh.instance_count = surviving_splats_count

    # 4. Décodage et Injection dans le MultiMesh — mode BATCH (PERF-04 fix)
    # On remplace les N appels set_instance_transform() / set_instance_custom_data()
    # par deux écritures en bloc via PackedFloat32Array, ~10-50× plus rapide.
    #
    # Format transform_array : 12 floats par instance (matrice 3×4, row-major)
    #   [m00 m01 m02 m03 | m10 m11 m12 m13 | m20 m21 m22 m23]
    # Pour une translation pure (Basis = IDENTITY) :
    #   [1 0 0 tx | 0 1 0 ty | 0 0 1 tz]
    #
    # Format custom_data_array : 4 floats par instance (RGBA Color)
    const TRANSFORM_FLOATS_PER_INSTANCE := 12
    const CUSTOM_FLOATS_PER_INSTANCE    := 4

    var xf_array  := PackedFloat32Array()
    var cd_array  := PackedFloat32Array()
    xf_array.resize(surviving_splats_count * TRANSFORM_FLOATS_PER_INSTANCE)
    cd_array.resize(surviving_splats_count * CUSTOM_FLOATS_PER_INSTANCE)

    # Tableau intermédiaire pour construire _original_transforms en une passe
    _original_transforms.resize(surviving_splats_count)

    for i in range(surviving_splats_count):
        var src := i * 16
        # Décoder position quantisée 16-bit → float monde
        var px := culled_bytes.decode_u16(src)     / 65535.0 * 10.0
        var py := culled_bytes.decode_u16(src + 2) / 65535.0 * 10.0
        var pz := culled_bytes.decode_u16(src + 4) / 65535.0 * 10.0

        # Remplir transform_array (translation pure, Basis = IDENTITY)
        var xf_off := i * TRANSFORM_FLOATS_PER_INSTANCE
        xf_array[xf_off]      = 1.0; xf_array[xf_off + 1]  = 0.0; xf_array[xf_off + 2]  = 0.0; xf_array[xf_off + 3]  = px
        xf_array[xf_off + 4]  = 0.0; xf_array[xf_off + 5]  = 1.0; xf_array[xf_off + 6]  = 0.0; xf_array[xf_off + 7]  = py
        xf_array[xf_off + 8]  = 0.0; xf_array[xf_off + 9]  = 0.0; xf_array[xf_off + 10] = 1.0; xf_array[xf_off + 11] = pz

        # Remplir custom_data_array
        var color_index := culled_bytes.decode_u16(src + 8)
        var covar_index := culled_bytes.decode_u16(src + 10)
        var opacity     := culled_bytes.decode_u8(src + 12) / 255.0
        var cd_off := i * CUSTOM_FLOATS_PER_INSTANCE
        cd_array[cd_off]     = float(color_index) / 65535.0
        cd_array[cd_off + 1] = float(covar_index) / 65535.0
        cd_array[cd_off + 2] = opacity
        cd_array[cd_off + 3] = 1.0

        # Cache des originaux pour le clay deformer
        _original_transforms[i] = Transform3D(Basis(), Vector3(px, py, pz))

    # Écriture en bloc dans le MultiMesh (un seul aller-retour GPU)
    multimesh.transform_array      = xf_array
    multimesh.custom_data_array    = cd_array

    print("FoveaEngine: %d splats injectés dans le MultiMesh (mode TRIANGLE, batch)." % surviving_splats_count)

    # Partager le cache avec le clay deformer si présent
    if deformer:
        deformer.set_original_transforms(multimesh, _original_transforms)

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