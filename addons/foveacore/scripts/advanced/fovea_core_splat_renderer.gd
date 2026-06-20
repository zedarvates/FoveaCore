class_name FoveaCoreSplatRenderer
extends MultiMeshInstance3D

## FoveaEngine : Moteur de rendu MultiMesh pour les Gaussian Splats
## VERSION TRIANGLE - Utilise un maillage triangulaire au lieu de quads
## Optimisation : réduction drastique du coût du fragment shader

@export_file("*.fovea") var asset_path: String = "":
    set(val):
        var old_path := asset_path
        asset_path = val
        if old_path != "" and old_path != val:
            if culler_pipeline:
                culler_pipeline.unload_asset_buffers(old_path)
        if is_inside_tree() and asset_path != "":
            load_and_render_splats()
            if enable_palette:
                load_palette_from_fovea()
            update_material_shader()
            call_deferred("_upload_covar_codebook")
@export var cull_threshold: float = 0.0 # 0.0 = Cull tout ce qui dépasse 90 degrés
@export var use_triangle_mesh: bool = true  # Utiliser le maillage triangle optimisé
@export var splat_subdivisions: int = 16    # Nombre de segments pour l'ellipse
@export var sort_distance_threshold: float = 0.1  # Distance minimale de déplacement de la caméra pour recalculer le tri/culling
@export var chunk_load_radius: float = 20.0  # Distance maximum pour charger un chunk spatial
@export var enable_layered_splatting: bool = true
@export var enable_gpu_driven: bool = false

@export_group("Cleaning (FoveaSplatCleaner)")
## Activer le filtrage des floaters et NaN apres le GPU culling
@export var enable_cleaning: bool = true:
    set(val):
        enable_cleaning = val
        if culler_pipeline:
            culler_pipeline.enable_cleaning = val
            _on_cleaning_parameter_changed()
## Radius de voisinage pour la detection des floaters (cellules voxel)
@export_range(1, 4) var floater_neighbor_radius: int = 1:
    set(val):
        floater_neighbor_radius = val
        if culler_pipeline:
            culler_pipeline.floater_neighbor_radius = val
            _on_cleaning_parameter_changed()
## Nombre minimum de voisins pour qu'un splat soit conserve
@export_range(1, 10) var floater_min_neighbors: int = 2:
    set(val):
        floater_min_neighbors = val
        if culler_pipeline:
            culler_pipeline.floater_min_neighbors = val
            _on_cleaning_parameter_changed()
## Decimer le nuage de points apres le nettoyage
@export var enable_decimation: bool = false:
    set(val):
        enable_decimation = val
        if culler_pipeline:
            culler_pipeline.enable_decimation = val
            _on_cleaning_parameter_changed()
## Cible apres decimation (0 = desactive)
@export var decimation_target: int = 50000:
    set(val):
        decimation_target = val
        if culler_pipeline:
            culler_pipeline.decimation_target = val
            _on_cleaning_parameter_changed()
## Fusionner les splats co-planaires pour réduire le GPU overdraw (Phase 3)
@export var enable_coplanar_merge: bool = false:
    set(val):
        enable_coplanar_merge = val
        if culler_pipeline:
            culler_pipeline.enable_coplanar_merge = val
            _on_cleaning_parameter_changed()
## Taille du bucket de profondeur Z pour la fusion co-planaire (valeur plus petite = plus agressif)
@export_range(128, 2048, 128) var coplanar_z_bucket: int = 512:
    set(val):
        coplanar_z_bucket = val
        if culler_pipeline:
            culler_pipeline.coplanar_z_bucket = val
            _on_cleaning_parameter_changed()
## Nombre minimum de splats dans un groupe pour déclencher la fusion
@export_range(2, 16) var coplanar_min_group: int = 4:
    set(val):
        coplanar_min_group = val
        if culler_pipeline:
            culler_pipeline.coplanar_min_group = val
            _on_cleaning_parameter_changed()

@export_group("Temporal Sorting (Phase 3)")
## Facteur d'entrelacement du tri GPU.
## 1 = tri complet chaque frame (qualite max, GPU stall max).
## 2 = la moitie des splats est retrie chaque frame (bon compromis).
## 4 = un quart par frame — recommande pour VR 90Hz (temps GPU strict).
@export_enum("Full:1", "Half:2", "Quarter:4") var sort_interleave_factor: int = 4

@export_group("Motion-Adaptive Splatting (Phase 3)")
## Activer le LOD adaptatif à la vélocité caméra (réduit la charge GPU en mouvement rapide)
@export var enable_motion_lod: bool = true
## Seuil de vitesse (m/s) au-dessus duquel le LOD se dégrade
@export var motion_speed_threshold: float = 1.5
## LOD minimum appliqué à pleine vitesse (0.2 = 20% des splats seulement)
@export_range(0.05, 1.0, 0.05) var motion_lod_minimum: float = 0.25
## Activer l'étirement des splats dans la direction du mouvement (motion blur natif)
@export var enable_motion_stretch: bool = true
## Facteur maximal d'étirement à haute vitesse
@export_range(0.0, 5.0, 0.1) var motion_stretch_max: float = 2.5

@export_group("Color Palette & Dithering (Phase 3)")
## Activer l'utilisation de la palette 8-bit si presente dans l'asset .fovea
@export var enable_palette: bool = true
## Activer le dithering Floyd-Steinberg pour masquer le banding
@export var use_dithering: bool = true
## Intensite du dithering Floyd-Steinberg
@export_range(0.0, 2.0) var dither_strength: float = 1.0

@export_group("MIP-Splatting & HLOD")
## Activer le système de niveaux de détail hiérarchiques (HLOD)
@export var enable_hlod := true
## Tailles de grille de voxelisation 3D pour chaque niveau HLOD (LOD 1, 2, 3)
@export var hlod_voxel_sizes: Array[float] = [0.2, 0.8, 3.0]
## Seuils de distance de caméra pour transiter entre les niveaux HLOD
@export var hlod_distances: Array[float] = [8.0, 18.0, 30.0]
## Activer le rendu par tuiles d'écran (16x16) via Compute Shader (Tile-Based Rasterization)
@export var enable_tile_rasterizer := false

@export_group("Surface Waves (Dynamic, Repeating & Looping)")
## Activer les vagues de surface dynamique (GPU)
@export var enable_waves: bool = false:
    set(val):
        enable_waves = val
        update_material_shader()
## Vitesse des vagues
@export var wave_speed: float = 1.0:
    set(val):
        wave_speed = val
        update_material_shader()
## Amplitude (hauteur) des vagues
@export var wave_amplitude: float = 0.2:
    set(val):
        wave_amplitude = val
        update_material_shader()
## Fréquence (densité) spatiale des vagues
@export var wave_frequency: float = 0.5:
    set(val):
        wave_frequency = val
        update_material_shader()
## Taille de pavage spatial (tiling)
@export var wave_tiling_size: float = 10.0:
    set(val):
        wave_tiling_size = val
        update_material_shader()
## Période de bouclage temporel (en secondes)
@export var wave_loop_period: float = 4.0:
    set(val):
        wave_loop_period = val
        update_material_shader()

var hlod_levels := {}
var _current_hlod_level := 0
var _original_splats: Array[GaussianSplat] = []

var _compositor_effect_added := false
var _compositor_effect: FoveaCompositorEffect = null

var culler_pipeline: GPUCullerPipeline
var splat_mesh: ArrayMesh
var triangle_mesh_generator

var texture_rd_output: Texture2DRD = null
var texture_rd_counter: Texture2DRD = null

## Référence optionnelle au FoveaClayDeformer attaché à ce renderer.
## Peut être assigné manuellement ou automatiquement par le deformer lui-même.
var deformer: FoveaClayDeformer = null

## Cache des transforms originaux (état de repos), alimenté après chaque load.
## Partagé avec le deformer pour un accès non-destructif.
var _original_transforms: Array[Transform3D] = []
var _last_camera_pos: Vector3 = Vector3.ZERO

## Suivi de la vélocité caméra pour le Motion-Adaptive LOD
var _prev_cam_pos: Vector3   = Vector3.ZERO
var _motion_lod_applied: float = 1.0  # Cache du lod_ratio courant pour éviter les envois inutiles

var _cached_main_light: DirectionalLight3D = null

func _ready() -> void:
    culler_pipeline = GPUCullerPipeline.new()
    culler_pipeline.interleave_factor = sort_interleave_factor
    _propagate_cleaning_parameters()
    
    # Charger le générateur de maillage triangle
    triangle_mesh_generator = load("res://addons/foveacore/scripts/advanced/triangle_splat_mesh.gd")
    
    # 1. Création de la géométrie de base (Maillage TRIANGLE)
    if use_triangle_mesh:
        splat_mesh = triangle_mesh_generator.generate_triangle_splat_mesh_optimized()
    else:
        # Fallback: QuadMesh classique (ancienne méthode)
        var quad_mesh: QuadMesh = QuadMesh.new()
        quad_mesh.size = Vector2(1.0, 1.0)
        # Convertir le quad en ArrayMesh pour compatibilité
        var st: SurfaceTool = SurfaceTool.new()
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
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = preload("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
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

    if camera and not _compositor_effect_added:
        _setup_compositor_effect(camera)

    if _compositor_effect and _compositor_effect.culler_pipeline:
        _compositor_effect.cached_hlod_distances = hlod_distances
        _compositor_effect.enable_tile_rasterizer = enable_tile_rasterizer
        _compositor_effect.fovea_asset_path = asset_path
        _compositor_effect.target_camera = camera
        
        var c_pipe: GPUCullerPipeline = _compositor_effect.culler_pipeline
        c_pipe.last_model_transform = global_transform
        c_pipe.last_use_palette = enable_palette
        
        var mat := material_override as ShaderMaterial
        if mat:
            var covar_tex: Variant = mat.get_shader_parameter("covar_texture")
            var palette_tex: Variant = mat.get_shader_parameter("palette_texture")
            if covar_tex:
                c_pipe.last_covar_texture_rid = covar_tex.get_rid()
            if palette_tex:
                c_pipe.last_palette_texture_rid = palette_tex.get_rid()
            
            var aabb_min_val: Variant = mat.get_shader_parameter("aabb_min")
            if aabb_min_val != null:
                c_pipe.last_aabb_min = aabb_min_val
            var aabb_max_val: Variant = mat.get_shader_parameter("aabb_max")
            if aabb_max_val != null:
                c_pipe.last_aabb_max = aabb_max_val
                
            var palette_size_val: Variant = mat.get_shader_parameter("palette_size")
            if palette_size_val != null:
                c_pipe.last_palette_size = int(palette_size_val)

    # Mettre à jour le culling/tri en temps réel si la caméra bouge (rendu par fichier uniquement)
    # ou si de nouveaux chunks ont été chargés asynchronement.
    var cam_pos: Vector3 = camera.global_position
    var camera_moved := (cam_pos - _last_camera_pos).length() > sort_distance_threshold
    var new_chunks_loaded := false
    var streaming_mgr: RefCounted = culler_pipeline.streaming_manager if culler_pipeline else null
    if _compositor_effect and _compositor_effect.culler_pipeline:
        streaming_mgr = _compositor_effect.culler_pipeline.streaming_manager
        
    if streaming_mgr:
        if streaming_mgr.has_newly_loaded_chunks:
            new_chunks_loaded = true
            streaming_mgr.has_newly_loaded_chunks = false

    if asset_path != "" and (camera_moved or new_chunks_loaded):
        _last_camera_pos = cam_pos
        if enable_tile_rasterizer:
            multimesh.instance_count = 0
            if streaming_mgr:
                streaming_mgr.update_streaming(camera, chunk_load_radius)
        else:
            load_and_render_splats()

    # Gérer la transition HLOD pour les splats procéduraux
    if enable_hlod and not hlod_levels.is_empty():
        _update_hlod_selection(cam_pos)

    var dist := global_position.distance_to(camera.global_position)

    # Calcul dynamique du ratio LOD stochastique selon la distance
    var lod := 1.0
    if dist > 25.0:
        lod = 0.15   # Rend seulement 15% des splats au loin
    elif dist > 15.0:
        lod = 0.40   # Rend 40% à moyenne distance
    elif dist > 8.0:
        lod = 0.75   # Rend 75% de près

    # ── Motion-Adaptive Splatting (Phase 3) ──────────────────────────────────
    # Réduit dynamiquement le LOD et étire les splats selon la vélocité caméra.
    # En VR à 90 Hz, une rotation rapide de la tête passe facilement à 2-4 m/s.
    # En mode motion, on rendu moins de splats (moins de fillrate) et on les
    # étire dans la direction du mouvement (motion blur natif gratuit).
    var mat := material_override as ShaderMaterial
    if mat:
        if enable_motion_lod and _delta > 0.0001:
            var cam_vel_world: Vector3 = (cam_pos - _prev_cam_pos) / _delta
            var speed: float           = cam_vel_world.length()

            if speed > motion_speed_threshold:
                # Interpolation linéaire vers le LOD minimum selon la vitesse
                var over_threshold: float = speed - motion_speed_threshold
                var motion_t: float = clampf(over_threshold / motion_speed_threshold, 0.0, 1.0)
                lod = lerpf(lod, motion_lod_minimum, motion_t)

                if enable_motion_stretch:
                    # Projeter la vélocité monde à l'espace vue pour la direction écran
                    var view_basis: Basis = camera.get_camera_transform().affine_inverse().basis
                    var vel_view: Vector3 = view_basis * cam_vel_world
                    var motion_dir_2d := Vector2(vel_view.x, -vel_view.y)  # flip Y screen
                    if motion_dir_2d.length() > 0.001:
                        motion_dir_2d = motion_dir_2d.normalized()
                    var stretch: float = motion_t * motion_stretch_max
                    mat.set_shader_parameter("motion_dir_screen",     motion_dir_2d)
                    mat.set_shader_parameter("motion_stretch_factor", stretch)
                else:
                    mat.set_shader_parameter("motion_stretch_factor", 0.0)
            else:
                # Retour progressif à la qualité maximale (smooth recovery)
                if enable_motion_stretch:
                    var current_stretch: float = mat.get_shader_parameter("motion_stretch_factor")
                    if current_stretch > 0.01:
                        mat.set_shader_parameter("motion_stretch_factor",
                            lerpf(current_stretch, 0.0, 0.15))  # Decay progressif
                    else:
                        mat.set_shader_parameter("motion_stretch_factor", 0.0)

        mat.set_shader_parameter("lod_ratio", lod)
        mat.set_shader_parameter("enable_layered_splatting", enable_layered_splatting)
        
        # Update light direction in shader for dynamic specular calculations
        var main_light: DirectionalLight3D = _find_main_light()
        if main_light:
            var light_dir: Vector3 = -main_light.global_transform.basis.z.normalized()
            mat.set_shader_parameter("light_direction", light_dir)
            
        _prev_cam_pos = cam_pos

    # Passe de déformation Clay (non-destructif : opère sur les originaux)
    if deformer and deformer.enabled and multimesh and multimesh.instance_count > 0:
        deformer.deform_multimesh(multimesh)

func _setup_compositor_effect(camera: Camera3D) -> void:
    if camera == null:
        return
    if camera.compositor == null:
        camera.compositor = Compositor.new()
    
    # Vérifier si l'effet est déjà présent
    for effect in camera.compositor.compositor_effects:
        if effect is FoveaCompositorEffect:
            _compositor_effect = effect
            _compositor_effect_added = true
            _compositor_effect.target_renderer = self
            _compositor_effect.fovea_asset_path = asset_path
            return
            
    _compositor_effect = FoveaCompositorEffect.new()
    _compositor_effect.target_camera = camera
    _compositor_effect.fovea_asset_path = asset_path
    _compositor_effect.target_renderer = self
    camera.compositor.compositor_effects.append(_compositor_effect)
    _compositor_effect_added = true
    print("FoveaCoreSplatRenderer: FoveaCompositorEffect successfully registered on camera compositor.")

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
    print("FoveaCoreSplatRenderer: Palette '%s' (%d colors) applied to shader." % \
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
        var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
        if loader and loader.has_method("load_covariance_codebook"):
            codebook_bytes = loader.load_covariance_codebook(asset_path)

    if codebook_bytes.is_empty():
        # Pas de codebook dans ce fichier .fovea : fallback sphere isotrope
        push_warning("FoveaCoreSplatRenderer: Pas de codebook covariance dans '%s'. Splats isotropes." % asset_path)
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
    print("FoveaCoreSplatRenderer: Codebook covariance charge : %d entrees (Splats anisotropes)." % k)

## Load palette from .fovea file and apply to material
func load_palette_from_fovea() -> void:
    if not ClassDB.can_instantiate("FoveaAssetLoader"):
        push_warning("FoveaCoreSplatRenderer: FoveaAssetLoader GDExtension not available for palette.")
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
    
    if mat.shader and mat.shader.resource_path.ends_with("splat_render_artistic.gdshader"):
        TexturedSplatGenerator.apply_brush_textures(mat)
        mat.set_shader_parameter("enable_waves", enable_waves)
        mat.set_shader_parameter("wave_speed", wave_speed)
        mat.set_shader_parameter("wave_amplitude", wave_amplitude)
        mat.set_shader_parameter("wave_frequency", wave_frequency)
        mat.set_shader_parameter("wave_tiling_size", wave_tiling_size)
        mat.set_shader_parameter("wave_loop_period", wave_loop_period)
        return
    
    var has_palette := false
    if enable_palette and ClassDB.can_instantiate("FoveaAssetLoader") and asset_path != "":
        var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
        if loader and loader.has_method("load_color_palette"):
            var palette_bytes: PackedByteArray = loader.load_color_palette(asset_path)
            has_palette = not palette_bytes.is_empty()
            
    if has_palette and use_dithering:
        mat.shader = preload("res://addons/foveacore/shaders/splat_render_triangle_palette.gdshader")
        mat.set_shader_parameter("use_dithering", true)
        mat.set_shader_parameter("dither_strength", dither_strength)
        print("FoveaCoreSplatRenderer: Utilizing splat_render_triangle_palette shader with Floyd-Steinberg dithering.")
    else:
        mat.shader = preload("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
        mat.set_shader_parameter("use_palette", has_palette)
        
    mat.set_shader_parameter("enable_waves", enable_waves)
    mat.set_shader_parameter("wave_speed", wave_speed)
    mat.set_shader_parameter("wave_amplitude", wave_amplitude)
    mat.set_shader_parameter("wave_frequency", wave_frequency)
    mat.set_shader_parameter("wave_tiling_size", wave_tiling_size)
    mat.set_shader_parameter("wave_loop_period", wave_loop_period)

func load_and_render_splats() -> void:
    var camera: Camera3D = get_viewport().get_camera_3d()
    if not camera:
        push_error("FoveaCoreSplatRenderer: No camera in viewport.")
        return
    var cam_pos: Vector3 = camera.global_position
    _last_camera_pos = cam_pos
    
    # Get depth texture from camera if available
    var depth_tex: RID = RID()
    if camera.has_method("get_camera_attributes") and camera.get_camera_attributes():
        var attrs: Variant = camera.get_camera_attributes()
        if attrs.has_method("get_depth_texture"):
            depth_tex = attrs.get_depth_texture()
    elif "attributes" in camera and camera.attributes:
        var attrs: Variant = camera.attributes
        if attrs.has_method("get_depth_texture"):
            depth_tex = attrs.get_depth_texture()
    
    # 2. Récupérer l'AABB depuis le fichier .fovea si possible
    var aabb_min := Vector3(-5, -5, -5)
    var aabb_max := Vector3(5, 5, 5)
    if ClassDB.can_instantiate("FoveaAssetLoader"):
        var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
        if loader and loader.has_method("get_asset_aabb"):
            var aabb_val: Variant = loader.get_asset_aabb(asset_path)
            if aabb_val is AABB:
                var aabb: AABB = aabb_val
                if aabb.size.length_squared() > 0.001:
                    aabb_min = aabb.position
                    aabb_max = aabb.end

    # Injecter l'AABB dans le shader material pour la dé-quantisation
    var mat := material_override as ShaderMaterial
    if mat:
        mat.set_shader_parameter("aabb_min", aabb_min)
        mat.set_shader_parameter("aabb_max", aabb_max)

    # 3. Exécution du Compute Shader ultra-rapide (Culling)
    culler_pipeline.chunk_load_radius = chunk_load_radius
    culler_pipeline.skip_sync = enable_gpu_driven
    var output_buffer_rid: RID = culler_pipeline.process_splats_from_file(
        asset_path, camera, depth_tex, cull_threshold, aabb_min, aabb_max, null, hlod_distances)
    if not output_buffer_rid.is_valid():
        return
        
    if enable_gpu_driven:
        var cache: Dictionary = culler_pipeline._gpu_buffers.get(asset_path, {})
        if not cache.is_empty():
            var out_rid: RID = cache.get("output_texture", RID())
            var cnt_rid: RID = cache.get("counter_texture", RID())
            if out_rid.is_valid() and cnt_rid.is_valid():
                if texture_rd_output == null:
                    texture_rd_output = Texture2DRD.new()
                if texture_rd_counter == null:
                    texture_rd_counter = Texture2DRD.new()
                
                if texture_rd_output.texture_rd_rid != out_rid:
                    texture_rd_output.texture_rd_rid = out_rid
                if texture_rd_counter.texture_rd_rid != cnt_rid:
                    texture_rd_counter.texture_rd_rid = cnt_rid
                
                if mat:
                    mat.set_shader_parameter("enable_gpu_driven", true)
                    mat.set_shader_parameter("output_texture", texture_rd_output)
                    mat.set_shader_parameter("counter_texture", texture_rd_counter)
                
                var streaming_asset = culler_pipeline.streaming_manager.register_asset(asset_path, aabb_min, aabb_max)
                if streaming_asset:
                    multimesh.instance_count = streaming_asset.total_splats
            else:
                push_error("FoveaCoreSplatRenderer: GPU-driven textures not valid in cache.")
        else:
            push_error("FoveaCoreSplatRenderer: Cache not found for asset: " + asset_path)
        return
        
    # 3. Récupération des données filtrées depuis la VRAM
    if culler_pipeline == null or culler_pipeline.rd == null:
        push_error("FoveaCoreSplatRenderer: culler_pipeline or rd is null, skipping data readback.")
        return
    var culled_bytes: PackedByteArray = culler_pipeline.rd.buffer_get_data(output_buffer_rid)
    
    # Chaque splat compressé fait 16 octets (SPLAT_BYTE_SIZE dans le culler)
    var surviving_splats_count: int = int(culled_bytes.size() / 16)
    print("FoveaEngine: %d splats GPU après culling." % surviving_splats_count)

    # 4b. Passe de nettoyage optionnelle (FoveaSplatCleaner — P3)
    # Désormais appliquée de manière statique au chargement dans culler_pipeline pour de meilleures performances.
    var statically_cleaned: bool = (culler_pipeline and culler_pipeline.enable_cleaning)
    if enable_cleaning and surviving_splats_count > 0 and not statically_cleaned:
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

    # Passe de fusion co-planaire (Coplanar Splat Merging, Phase 3)
    # Regroupe les splats co-surfaciques pour éliminer l'overdraw GPU.
    var statically_merged: bool = (culler_pipeline and culler_pipeline.enable_coplanar_merge)
    if enable_coplanar_merge and surviving_splats_count > 0 and not statically_merged:
        culled_bytes = FoveaSplatCleaner.merge_coplanar(
            culled_bytes, coplanar_z_bucket, 24, 1024, coplanar_min_group)
        surviving_splats_count = culled_bytes.size() / 16

    multimesh.instance_count = surviving_splats_count

    # 4. Décodage PARALLÈLE — FoveaThreadPool (Phase 2 : Multithreading)
    # Répartit le décodage culled_bytes → xf_array/cd_array sur tous les
    # cœurs CPU via N threads Godot. Élimine la stall mono-thread de la
    # boucle séquentielle précédente (~10-50× plus rapide sur > 50k splats).
    var t_decode_start: int = Time.get_ticks_usec()
    var decode_result: FoveaThreadPool.DecodeResult = \
        FoveaThreadPool.decode_parallel(culled_bytes, surviving_splats_count, aabb_min, aabb_max)
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

    # En mode persistant, la libération du buffer GPU est gérée en interne par culler_pipeline lors du cleanup.
    pass

## Méthode pour mettre à jour dynamiquement le maillage
func update_splat_mesh_mode(use_triangle: bool) -> void:
    use_triangle_mesh = use_triangle
    if use_triangle:
        splat_mesh = triangle_mesh_generator.generate_triangle_splat_mesh_optimized()
    else:
        var quad_mesh: QuadMesh = QuadMesh.new()
        quad_mesh.size = Vector2(1.0, 1.0)
        var st: SurfaceTool = SurfaceTool.new()
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

## Rendu de splats non-quantisés passés sous forme de GaussianSplat (compatibilité avec FoveaCoreManager)
func render_splats(splats: Array[GaussianSplat]) -> int:
    _original_splats = splats
    if enable_hlod and not splats.is_empty():
        # Générer et mettre en cache la base de données HLOD
        hlod_levels = FoveaHLODGenerator.generate_hlod_levels(splats, hlod_voxel_sizes)
        _current_hlod_level = -1 # Forcer la transition initiale
        var camera: Camera3D = get_viewport().get_camera_3d()
        var cam_pos: Vector3 = camera.global_position if camera else Vector3.ZERO
        _update_hlod_selection(cam_pos, true)
        return _original_splats.size()
    else:
        hlod_levels.clear()
        return render_splats_internal(splats)

## Exécution du rendu interne pour un ensemble de splats donné
func render_splats_internal(splats: Array[GaussianSplat]) -> int:
    var count: int = splats.size()
    multimesh.instance_count = count

    if count == 0:
        return 0

    # Calcul de l'AABB à partir des splats
    var aabb_min: Vector3 = Vector3(INF, INF, INF)
    var aabb_max: Vector3 = Vector3(-INF, -INF, -INF)
    for s: GaussianSplat in splats:
        aabb_min = aabb_min.min(s.position)
        aabb_max = aabb_max.max(s.position)

    # Marges sur l'AABB
    aabb_min -= Vector3(0.1, 0.1, 0.1)
    aabb_max += Vector3(0.1, 0.1, 0.1)

    # Injecter l'AABB dans le shader
    var mat := material_override as ShaderMaterial
    if mat:
        mat.set_shader_parameter("aabb_min", aabb_min)
        mat.set_shader_parameter("aabb_max", aabb_max)
        mat.set_shader_parameter("use_palette", false)
        mat.set_shader_parameter("enable_layered_splatting", enable_layered_splatting)

    # Packer les splats en format 16-octets
    var raw_bytes: PackedByteArray = pack_gaussian_splats(splats, aabb_min, aabb_max)

    # Décoder de façon parallèle
    var decode_result: FoveaThreadPool.DecodeResult = FoveaThreadPool.decode_parallel(raw_bytes, count, aabb_min, aabb_max)

    # Assigner au MultiMesh
    multimesh.transform_array = decode_result.xf_array
    multimesh.custom_data_array = decode_result.cd_array

    _original_transforms = decode_result.original_transforms

    return count

## Sélectionne et applique dynamiquement le niveau HLOD approprié
func _update_hlod_selection(camera_pos: Vector3, force: bool = false) -> void:
    if not enable_hlod or hlod_levels.is_empty():
        return
        
    var dist := global_position.distance_to(camera_pos)
    
    var target_hlod := 0
    for idx in range(hlod_distances.size()):
        if dist >= hlod_distances[idx]:
            target_hlod = idx + 1
            
    if target_hlod != _current_hlod_level or force:
        _current_hlod_level = target_hlod
        if hlod_levels.has(target_hlod):
            var splats_to_render: Array[GaussianSplat] = hlod_levels[target_hlod]
            render_splats_internal(splats_to_render)
            print("FoveaCoreSplatRenderer: Passage au niveau HLOD %d (%d splats) à une distance de %.2f m" % [
                target_hlod, splats_to_render.size(), dist
            ])

## Packs GaussianSplat objects into a raw 16-byte PackedSplat array compatible with the shader
func pack_gaussian_splats(splats: Array[GaussianSplat], aabb_min: Vector3, aabb_max: Vector3) -> PackedByteArray:
    var bytes: PackedByteArray = PackedByteArray()
    bytes.resize(splats.size() * 16)

    var range_x: float = max(aabb_max.x - aabb_min.x, 0.001)
    var range_y: float = max(aabb_max.y - aabb_min.y, 0.001)
    var range_z: float = max(aabb_max.z - aabb_min.z, 0.001)

    for i: int in range(splats.size()):
        var s: GaussianSplat = splats[i]
        var src: int = i * 16

        # Quantize position
        var qx: int = int(clamp((s.position.x - aabb_min.x) / range_x * 65535.0, 0, 65535))
        var qy: int = int(clamp((s.position.y - aabb_min.y) / range_y * 65535.0, 0, 65535))
        var qz: int = int(clamp((s.position.z - aabb_min.z) / range_z * 65535.0, 0, 65535))

        bytes.encode_u16(src, qx)
        bytes.encode_u16(src + 2, qy)
        bytes.encode_u16(src + 4, qz)

        # Encodage de la direction d'écoulement (normal.x et normal.z mappés de -1..1 à 0..255)
        var nx: int = int(clamp((s.normal.x * 0.5 + 0.5) * 255.0, 0, 255))
        var nz: int = int(clamp((s.normal.z * 0.5 + 0.5) * 255.0, 0, 255))
        bytes.encode_u8(src + 6, nx)
        bytes.encode_u8(src + 7, nz)

        # Color index / RGB565
        var r5: int = int(clamp(s.color.r * 31.0, 0, 31))
        var g6: int = int(clamp(s.color.g * 63.0, 0, 63))
        var b5: int = int(clamp(s.color.b * 31.0, 0, 31))
        var rgb565: int = (r5 << 11) | (g6 << 5) | b5

        bytes.encode_u16(src + 8, rgb565)
        # covar_index (0 = isotropic default)
        bytes.encode_u16(src + 10, 0)

        # Opacity
        var op: int = int(clamp(s.opacity * 255.0, 0, 255))
        bytes.encode_u8(src + 12, op)
        # layer_id, dither_seed, brush_type (shape type)
        bytes.encode_u8(src + 13, int(s.layer_type))
        bytes.encode_u8(src + 14, s.dither_seed)
        bytes.encode_u8(src + 15, int(s.brush_type))

    return bytes

func _exit_tree() -> void:
    if culler_pipeline:
        culler_pipeline.cleanup()

func _propagate_cleaning_parameters() -> void:
    if culler_pipeline:
        culler_pipeline.enable_cleaning = enable_cleaning
        culler_pipeline.floater_neighbor_radius = floater_neighbor_radius
        culler_pipeline.floater_min_neighbors = floater_min_neighbors
        culler_pipeline.enable_decimation = enable_decimation
        culler_pipeline.decimation_target = decimation_target
        culler_pipeline.enable_coplanar_merge = enable_coplanar_merge
        culler_pipeline.coplanar_z_bucket = coplanar_z_bucket
        culler_pipeline.coplanar_min_group = coplanar_min_group

func _on_cleaning_parameter_changed() -> void:
    if culler_pipeline:
        culler_pipeline.clear_cache()
    if asset_path != "" and is_inside_tree():
        load_and_render_splats()

func _find_main_light() -> DirectionalLight3D:
    if is_instance_valid(_cached_main_light):
        return _cached_main_light
    if not is_inside_tree():
        return null
    var lights: Array[Node] = get_tree().get_nodes_in_group("directional_lights")
    for light in lights:
        if light is DirectionalLight3D:
            _cached_main_light = light
            return light
    var current_scene: Node = get_tree().current_scene
    if current_scene:
        var found: DirectionalLight3D = _find_light_recursive(current_scene)
        if found:
            _cached_main_light = found
            return found
    var found_root := _find_light_recursive(get_tree().root)
    if found_root:
        _cached_main_light = found_root
        return found_root
    return null

func _find_light_recursive(node: Node) -> DirectionalLight3D:
    if node is DirectionalLight3D:
        return node
    for child in node.get_children():
        var found: DirectionalLight3D = _find_light_recursive(child)
        if found:
            return found
    return null