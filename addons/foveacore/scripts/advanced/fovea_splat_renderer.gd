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
## Activer le filtrage des floaters et NaN apres le GPU culling
@export var enable_cleaning: bool = true
## Radius de voisinage pour la detection des floaters (cellules voxel)
@export_range(1, 4) var floater_neighbor_radius: int = 1
## Nombre minimum de voisins pour qu'un splat soit conserve
@export_range(1, 10) var floater_min_neighbors: int = 2
## Decimer le nuage de points apres le nettoyage
@export var enable_decimation: bool = false
## Cible apres decimation (0 = desactive)
@export var decimation_target: int = 50000

@export_group("Temporal Sorting (Phase 3)")
## Facteur d'entrelacement du tri GPU.
## 1 = tri complet chaque frame (qualite max, GPU stall max).
## 2 = la moitie des splats est retrie chaque frame (bon compromis).
## 4 = un quart par frame — recommande pour VR 90Hz (temps GPU strict).
@export_enum("Full:1", "Half:2", "Quarter:4") var sort_interleave_factor: int = 4

@export_group("Color Palette & Dithering (Phase 3)")
## Activer l'utilisation de la palette 8-bit si presente dans l'asset .fovea
@export var enable_palette: bool = true
## Activer le dithering Floyd-Steinberg pour masquer le banding
@export var use_dithering: bool = true
## Intensite du dithering Floyd-Steinberg
@export_range(0.0, 2.0) var dither_strength: float = 1.0

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
    culler_pipeline.interleave_factor = sort_interleave_factor
    
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

    # Texture covariance par defaut (sphere unite) : evite la lecture de texture vide
    # Elle sera remplacee par le vrai codebook apres le chargement du fichier .fovea
    _set_default_covar_texture()

    if asset_path != "":
        load_and_render_splats()
        if enable_palette:
            load_palette_from_fovea()
        update_material_shader()
        call_deferred("_upload_covar_codebook")

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

## Upload de la texture covariance par defaut (sphere unite 1x1)
## Garantit que le shader ne lit jamais une texture non-initialisee
func _set_default_covar_texture() -> void:
    # Format : 2 colonnes x 1 ligne, RGBAF (32-bit float par canal)
    # Col 0 (u=0.25) : scale=(0,0,0), rot_w=1.0  -> exp(scale) = (1,1,1) = sphere unite
    # Col 1 (u=0.75) : rot_xyz=(0,0,0), pad=0
    var default_data: PackedByteArray = PackedByteArray()
    default_data.resize(32)  # 2 pixels x 4 canaux x 4 bytes (float32)
    # Pixel 0 : scale_x=0, scale_y=0, scale_z=0, rot_w=1
    default_data.encode_float(0,  0.0)   # scale_x
    default_data.encode_float(4,  0.0)   # scale_y
    default_data.encode_float(8,  0.0)   # scale_z
    default_data.encode_float(12, 1.0)   # rot_w
    # Pixel 1 : rot_x=0, rot_y=0, rot_z=0, pad=0
    default_data.encode_float(16, 0.0)   # rot_x
    default_data.encode_float(20, 0.0)   # rot_y
    default_data.encode_float(24, 0.0)   # rot_z
    default_data.encode_float(28, 0.0)   # pad

    var img: Image = Image.create_from_data(2, 1, false, Image.FORMAT_RGBAF, default_data)
    var tex: ImageTexture = ImageTexture.create_from_image(img)

    var mat := material_override as ShaderMaterial
    if mat:
        mat.set_shader_parameter("covar_texture", tex)

## Upload du codebook de covariance depuis le fichier .fovea (Phase 3 : Anisotropic Splats)
## Appelee via call_deferred() apres load_and_render_splats() pour ne pas bloquer _ready()
func _upload_covar_codebook() -> void:
    if asset_path == "":
        return

    var mat := material_override as ShaderMaterial
    if mat == null:
        return

    # Tentative de chargement via GDExtension Rust
    var codebook_bytes: PackedByteArray = PackedByteArray()
    if ClassDB.can_instantiate("FoveaAssetLoader"):
        var loader = ClassDB.instantiate("FoveaAssetLoader")
        if loader and loader.has_method("load_covariance_codebook"):
            codebook_bytes = loader.load_covariance_codebook(asset_path)

    if codebook_bytes.is_empty():
        # Pas de codebook dans ce fichier .fovea : fallback sphere isotrope
        push_warning("FoveaSplatRenderer: Pas de codebook covariance dans '%s'. Splats isotropes." % asset_path)
        return  # La texture par defaut (sphere unite) est deja en place

    # Le codebook est un tableau de K entrees de 7 floats : [sx, sy, sz, rw, rx, ry, rz]
    # Stockage dans une texture 2 colonnes x K lignes (FORMAT_RGBAF)
    var entry_size: int = 7 * 4  # 7 floats x 4 bytes
    var k: int = codebook_bytes.size() / entry_size
    if k == 0:
        return

    # Texture 2 x K pixels : col0 = (sx,sy,sz,rw), col1 = (rx,ry,rz,0)
    var tex_data: PackedByteArray = PackedByteArray()
    tex_data.resize(k * 2 * 4 * 4)  # K lignes x 2 pixels x 4 canaux x 4 bytes

    for i: int in range(k):
        var src: int = i * entry_size
        var dst: int = i * 32  # 2 pixels x 16 bytes par pixel
        # Col 0 : scale_xyz + rot_w
        tex_data.encode_float(dst,      codebook_bytes.decode_float(src))
        tex_data.encode_float(dst + 4,  codebook_bytes.decode_float(src + 4))
        tex_data.encode_float(dst + 8,  codebook_bytes.decode_float(src + 8))
        tex_data.encode_float(dst + 12, codebook_bytes.decode_float(src + 12))
        # Col 1 : rot_xyz + pad
        tex_data.encode_float(dst + 16, codebook_bytes.decode_float(src + 16))
        tex_data.encode_float(dst + 20, codebook_bytes.decode_float(src + 20))
        tex_data.encode_float(dst + 24, codebook_bytes.decode_float(src + 24))
        tex_data.encode_float(dst + 28, 0.0)

    var img: Image = Image.create_from_data(2, k, false, Image.FORMAT_RGBAF, tex_data)
    var tex: ImageTexture = ImageTexture.create_from_image(img)
    mat.set_shader_parameter("covar_texture", tex)
    print("FoveaSplatRenderer: Codebook covariance charge : %d entrees (Splats anisotropes)." % k)

## Load palette from .fovea file and apply to material
func load_palette_from_fovea() -> void:
    if not ClassDB.can_instantiate("FoveaAssetLoader"):
        push_warning("FoveaSplatRenderer: FoveaAssetLoader GDExtension not available for palette.")
        return

    var loader := ClassDB.instantiate("FoveaAssetLoader")
    if not loader or not loader.has_method("load_color_palette"):
        return

    var palette_bytes: PackedByteArray = loader.load_color_palette(asset_path)
    if palette_bytes.is_empty():
        return

    var palette_colors := palette_bytes.size() / 12 # 3 floats * 4 bytes per color
    if palette_colors == 0:
        return

    # Create palette resource from raw bytes
    var palette := FoveaColorPalette.new()
    palette.palette_name = asset_path.get_file() + " palette"
    palette.palette_size = palette_colors
    palette.colors.resize(palette_colors)
    for i in palette_colors:
        var r := palette_bytes.decode_float(i * 12)
        var g := palette_bytes.decode_float(i * 12 + 4)
        var b := palette_bytes.decode_float(i * 12 + 8)
        palette.colors[i] = Color(r, g, b)

    setup_palette(palette)

## Met a jour le shader du materiau en fonction de l'activation de la palette et du dithering
func update_material_shader() -> void:
    var mat := material_override as ShaderMaterial
    if not mat:
        return
    
    var has_palette := false
    if enable_palette and ClassDB.can_instantiate("FoveaAssetLoader") and asset_path != "":
        var loader = ClassDB.instantiate("FoveaAssetLoader")
        if loader and loader.has_method("load_color_palette"):
            var palette_bytes: PackedByteArray = loader.load_color_palette(asset_path)
            has_palette = not palette_bytes.is_empty()
            
    if has_palette and use_dithering:
        mat.shader = load("res://addons/foveacore/shaders/splat_render_triangle_palette.gdshader")
        mat.set_shader_parameter("use_dithering", true)
        mat.set_shader_parameter("dither_strength", dither_strength)
        print("FoveaSplatRenderer: Utilizing splat_render_triangle_palette shader with Floyd-Steinberg dithering.")
    else:
        mat.shader = load("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
        mat.set_shader_parameter("use_palette", has_palette)

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

    # 4. Décodage PARALLÈLE — FoveaThreadPool (Phase 2 : Multithreading)
    # Répartit le décodage culled_bytes → xf_array/cd_array sur tous les
    # cœurs CPU via N threads Godot. Élimine la stall mono-thread de la
    # boucle séquentielle précédente (~10-50× plus rapide sur > 50k splats).
    var t_decode_start: int = Time.get_ticks_usec()
    var decode_result: FoveaThreadPool.DecodeResult = \
        FoveaThreadPool.decode_parallel(culled_bytes, surviving_splats_count)
    var t_decode_ms: float = (Time.get_ticks_usec() - t_decode_start) / 1000.0
    print("FoveaEngine: Décodage parallèle de %d splats en %.2f ms (%d threads)." % [
        surviving_splats_count, t_decode_ms, OS.get_processor_count()])

    # Mettre à jour le cache des transforms originaux (pour FoveaClayDeformer)
    _original_transforms = decode_result.original_transforms

    # Écriture en bloc dans le MultiMesh (un seul aller-retour GPU)
    multimesh.transform_array   = decode_result.xf_array
    multimesh.custom_data_array = decode_result.cd_array

    print("FoveaEngine: %d splats injectés dans le MultiMesh (mode TRIANGLE, batch parallèle)." % surviving_splats_count)

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