class_name FoveaInstancedSplatRenderer
extends MultiMeshInstance3D

## FoveaEngine : Rendu d'instances multiples pour les Gaussian Splats (Global Splat Instancing)
## Phase 3 : Rendu de milliers de copies du même asset avec une seule copie en VRAM.

@export_file("*.fovea") var asset_path: String = ""
@export var cull_threshold: float = 0.0 # 0.0 = Cull tout ce qui dépasse 90 degrés
@export var use_triangle_mesh: bool = true
@export var splat_subdivisions: int = 16
@export var sort_distance_threshold: float = 0.1

## Liste des transformations (position, rotation, échelle) pour chaque instance
@export var instance_transforms: Array[Transform3D] = []

@export_group("Cleaning (FoveaSplatCleaner)")
@export var enable_cleaning: bool = true
@export_range(1, 4) var floater_neighbor_radius: int = 1
@export_range(1, 10) var floater_min_neighbors: int = 2
@export var enable_decimation: bool = false
@export var decimation_target: int = 50000
@export var enable_coplanar_merge: bool = false
@export_range(128, 2048, 128) var coplanar_z_bucket: int = 512
@export_range(2, 16) var coplanar_min_group: int = 4

@export_group("Color Palette & Dithering")
@export var enable_palette: bool = true
@export var use_dithering: bool = true
@export_range(0.0, 2.0) var dither_strength: float = 1.0

var instanced_culler: FoveaInstancedCuller
var splat_mesh: ArrayMesh
var triangle_mesh_generator
var _last_camera_pos: Vector3 = Vector3.ZERO
var _last_transforms: Array[Transform3D] = []
var _last_transforms_size: int = 0

var instance_colors: Array[Color] = []
var instance_scales: Array[float] = []
var instance_alphas: Array[float] = []
var _last_colors: Array[Color] = []
var _last_scales: Array[float] = []
var _last_alphas: Array[float] = []

func _ready() -> void:
	instanced_culler = FoveaInstancedCuller.new()
	triangle_mesh_generator = load("res://addons/foveacore/scripts/advanced/triangle_splat_mesh.gd")

	# 1. Création de la géométrie de base (Maillage TRIANGLE)
	if use_triangle_mesh:
		splat_mesh = triangle_mesh_generator.generate_triangle_splat_mesh_optimized()
	else:
		# Fallback: QuadMesh classique
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

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = splat_mesh

	var material = ShaderMaterial.new()
	material.shader = preload("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
	material.set_shader_parameter("splat_subdivisions", splat_subdivisions)
	material.set_shader_parameter("use_palette", false)
	material.set_shader_parameter("palette_size", 0)
	self.material_override = material

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

	# 0. Mettre à jour la liste des transforms et overrides d'instances depuis le groupe "splattables"
	var active_nodes = get_tree().get_nodes_in_group("splattables")
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var scales: Array[float] = []
	var alphas: Array[float] = []
	for n in active_nodes:
		if n is FoveaSplattable and n.splat_file_path == asset_path and n.visible and n.splatting_enabled:
			transforms.append(n.global_transform)
			colors.append(n.color_override)
			scales.append(n.scale_override)
			alphas.append(n.alpha_override)

	var changed := false
	if transforms.size() != _last_transforms_size:
		changed = true
	else:
		for i in range(transforms.size()):
			if not transforms[i].is_equal_approx(_last_transforms[i]):
				changed = true
				break
			if not colors[i].is_equal_approx(_last_colors[i]):
				changed = true
				break
			if not is_equal_approx(scales[i], _last_scales[i]):
				changed = true
				break
			if not is_equal_approx(alphas[i], _last_alphas[i]):
				changed = true
				break

	instance_transforms = transforms
	instance_colors = colors
	instance_scales = scales
	instance_alphas = alphas

	_last_transforms = transforms.duplicate()
	_last_colors = colors.duplicate()
	_last_scales = scales.duplicate()
	_last_alphas = alphas.duplicate()
	_last_transforms_size = transforms.size()

	# Recalculer le culling si la caméra bouge ou si les instances ont changé
	var cam_pos = camera.global_position
	if changed or (cam_pos - _last_camera_pos).length() > sort_distance_threshold:
		_last_camera_pos = cam_pos
		load_and_render_splats()

func load_and_render_splats() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera or not instanced_culler or instanced_culler.rd == null:
		return

	if asset_path == "" or not FileAccess.file_exists(asset_path):
		return

	# 1. Charger les octets bruts du fichier .fovea
	var raw_bytes := PackedByteArray()
	if ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("load_raw_splat_bytes"):
			raw_bytes = loader.load_raw_splat_bytes(asset_path)

	if raw_bytes.is_empty():
		# Fallback direct
		var file := FileAccess.open(asset_path, FileAccess.READ)
		if file:
			var all_bytes = file.get_buffer(file.get_length())
			file.close()
			
			if all_bytes.size() >= 8 and all_bytes.slice(0, 8).get_string_from_ascii() == "FOVEA_3D":
				var version = all_bytes.decode_u32(8)
				var header_size = 72 if version >= 2 else 48
				if all_bytes.size() >= header_size:
					var color_k = all_bytes.decode_u32(16)
					var covar_k = all_bytes.decode_u32(20)
					var palette_size = color_k * 12
					var covar_size = covar_k * 32
					var splats_start = header_size + palette_size + covar_size
					if all_bytes.size() >= splats_start:
						raw_bytes = all_bytes.slice(splats_start)
			elif all_bytes.size() >= 16:
				raw_bytes = all_bytes.slice(16)
			else:
				raw_bytes = all_bytes

	if raw_bytes.is_empty():
		push_error("FoveaInstancedSplatRenderer: Failed to load raw bytes from %s." % asset_path)
		return

	# 2. Récupérer l'AABB
	var aabb_min := Vector3(-5, -5, -5)
	var aabb_max := Vector3(5, 5, 5)
	if ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("get_asset_aabb"):
			var aabb: AABB = loader.get_asset_aabb(asset_path)
			if aabb.size.length_squared() > 0.001:
				aabb_min = aabb.position
				aabb_max = aabb.end

	var mat := material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("aabb_min", aabb_min)
		mat.set_shader_parameter("aabb_max", aabb_max)

	# 3. Récupérer la texture de profondeur de la caméra si possible
	var depth_tex: RID = RID()
	if camera.has_method("get_camera_attributes") and camera.get_camera_attributes():
		var attrs = camera.get_camera_attributes()
		if attrs.has_method("get_depth_texture"):
			depth_tex = attrs.get_depth_texture()
	elif "attributes" in camera and camera.attributes:
		var attrs = camera.attributes
		if attrs.has_method("get_depth_texture"):
			depth_tex = attrs.get_depth_texture()

	# 4. Culling GPU d'instances multiples
	var cull_res = instanced_culler.process_instanced_splats(
		raw_bytes,
		instance_transforms,
		camera,
		depth_tex,
		cull_threshold,
		aabb_min,
		aabb_max
	)

	var output_buffer_rid = cull_res.buffer_rid
	var surviving_splats_count = cull_res.count
	var active_instance_indices = cull_res.active_instance_indices

	if not output_buffer_rid.is_valid() or surviving_splats_count == 0:
		multimesh.instance_count = 0
		return

	# Lire les données filtrées depuis le GPU
	var culled_bytes: PackedByteArray = instanced_culler.rd.buffer_get_data(output_buffer_rid)

	# 5. Nettoyage GPU optionnel
	if enable_cleaning and surviving_splats_count > 0:
		var before_clean: int = surviving_splats_count
		culled_bytes = FoveaSplatCleaner.filter_nan_inf(culled_bytes)
		culled_bytes = FoveaSplatCleaner.filter_floaters(
			culled_bytes, floater_neighbor_radius, floater_min_neighbors)
		if enable_decimation and decimation_target > 0:
			culled_bytes = FoveaSplatCleaner.decimate(culled_bytes, decimation_target)
		surviving_splats_count = culled_bytes.size() / 16
		
	if enable_coplanar_merge and surviving_splats_count > 0:
		culled_bytes = FoveaSplatCleaner.merge_coplanar(
			culled_bytes, coplanar_z_bucket, 24, 1024, coplanar_min_group)
		surviving_splats_count = culled_bytes.size() / 16

	multimesh.instance_count = surviving_splats_count

	# Extraire les transforms et overrides correspondants aux instances visibles
	var active_transforms: Array[Transform3D] = []
	var active_colors: Array[Color] = []
	var active_scales: Array[float] = []
	var active_alphas: Array[float] = []
	for idx in active_instance_indices:
		active_transforms.append(instance_transforms[idx])
		active_colors.append(instance_colors[idx] if idx < instance_colors.size() else Color.WHITE)
		active_scales.append(instance_scales[idx] if idx < instance_scales.size() else 1.0)
		active_alphas.append(instance_alphas[idx] if idx < instance_alphas.size() else 1.0)

	# 6. Décodage parallèle
	var decode_result := FoveaThreadPool.decode_parallel(
		culled_bytes,
		surviving_splats_count,
		aabb_min,
		aabb_max,
		active_transforms,
		active_colors,
		active_scales,
		active_alphas
	)

	multimesh.transform_array = decode_result.xf_array
	multimesh.custom_data_array = decode_result.cd_array

	# Libérer le buffer GPU
	instanced_culler.rd.free_rid(output_buffer_rid)

func _set_default_covar_texture() -> void:
	var default_data := PackedByteArray()
	default_data.resize(32)
	default_data.encode_float(0,  0.0)
	default_data.encode_float(4,  0.0)
	default_data.encode_float(8,  0.0)
	default_data.encode_float(12, 1.0)
	default_data.encode_float(16, 0.0)
	default_data.encode_float(20, 0.0)
	default_data.encode_float(24, 0.0)
	default_data.encode_float(28, 0.0)

	var img := Image.create_from_data(2, 1, false, Image.FORMAT_RGBAF, default_data)
	var tex := ImageTexture.create_from_image(img)

	var mat := material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("covar_texture", tex)

func _upload_covar_codebook() -> void:
	if asset_path == "":
		return

	var mat := material_override as ShaderMaterial
	if mat == null:
		return

	var codebook_bytes := PackedByteArray()
	if ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("load_covariance_codebook"):
			codebook_bytes = loader.load_covariance_codebook(asset_path)

	if codebook_bytes.is_empty():
		return

	var entry_size := 7 * 4
	var k := codebook_bytes.size() / entry_size
	if k == 0:
		return

	var tex_data := PackedByteArray()
	tex_data.resize(k * 2 * 4 * 4)

	for i in range(k):
		var src := i * entry_size
		var dst := i * 32
		tex_data.encode_float(dst,      codebook_bytes.decode_float(src))
		tex_data.encode_float(dst + 4,  codebook_bytes.decode_float(src + 4))
		tex_data.encode_float(dst + 8,  codebook_bytes.decode_float(src + 8))
		tex_data.encode_float(dst + 12, codebook_bytes.decode_float(src + 12))
		tex_data.encode_float(dst + 16, codebook_bytes.decode_float(src + 16))
		tex_data.encode_float(dst + 20, codebook_bytes.decode_float(src + 20))
		tex_data.encode_float(dst + 24, codebook_bytes.decode_float(src + 24))
		tex_data.encode_float(dst + 28, 0.0)

	var img := Image.create_from_data(2, k, false, Image.FORMAT_RGBAF, tex_data)
	var tex := ImageTexture.create_from_image(img)
	mat.set_shader_parameter("covar_texture", tex)

func load_palette_from_fovea() -> void:
	if not ClassDB.can_instantiate("FoveaAssetLoader"):
		return
	var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
	if not loader or not loader.has_method("load_color_palette"):
		return
	var palette_bytes: PackedByteArray = loader.load_color_palette(asset_path)
	if palette_bytes.is_empty():
		return
	var palette_colors: int = palette_bytes.size() / 12
	if palette_colors == 0:
		return
	var palette := FoveaColorPalette.new()
	palette.palette_name = asset_path.get_file() + " palette"
	palette.palette_size = palette_colors
	palette.colors.resize(palette_colors)
	for i in palette_colors:
		var r: float = palette_bytes.decode_float(i * 12)
		var g: float = palette_bytes.decode_float(i * 12 + 4)
		var b: float = palette_bytes.decode_float(i * 12 + 8)
		palette.colors[i] = Color(r, g, b)
	setup_palette(palette)

func setup_palette(palette: FoveaColorPalette) -> void:
	if palette == null or palette.colors.is_empty():
		return
	var material := material_override as ShaderMaterial
	if material == null:
		return
	var data := palette.to_packed_rgb_array()
	var img := Image.create_from_data(1, palette.colors.size(), false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(img)
	tex.filter_clip = true
	material.set_shader_parameter("use_palette", true)
	material.set_shader_parameter("palette_texture", tex)
	material.set_shader_parameter("palette_size", palette.colors.size())

func update_material_shader() -> void:
	var mat := material_override as ShaderMaterial
	if not mat:
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
	else:
		mat.shader = preload("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
		mat.set_shader_parameter("use_palette", has_palette)

func _exit_tree() -> void:
	if instanced_culler:
		instanced_culler.cleanup()
