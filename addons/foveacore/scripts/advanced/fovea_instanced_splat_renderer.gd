class_name FoveaInstancedSplatRenderer
extends MultiMeshInstance3D

const FoveaInstancedSplatLayout := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_splat_layout.gd")
const FoveaAssetFormatLoaderScript := preload("res://addons/foveacore/scripts/fovea_asset_loader.gd")
const FoveaBinaryFormatScript := preload("res://addons/foveacore/scripts/fovea_binary_format.gd")

## FoveaEngine : Rendu d'instances multiples pour les Gaussian Splats (Global Splat Instancing)
## Phase 3 : Rendu de milliers de copies du même asset avec une seule copie en VRAM.

@export_file("*.fovea") var asset_path: String = ""
@export var cull_threshold: float = 0.0 # 0.0 = Cull tout ce qui dépasse 90 degrés
@export var use_triangle_mesh: bool = true
@export var splat_subdivisions: int = 16
@export var sort_distance_threshold: float = 0.1
@export var enable_layered_splatting: bool = true

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
## Opt-in until the compute output-count contract passes on the D3D12 baseline.
@export var enable_experimental_gpu_culling: bool = false
@export var enable_gpu_driven: bool = false
@export var use_gpu_instance_culling: bool = false

var texture_rd_output: Texture2DRD = null
var texture_rd_counter: Texture2DRD = null

var instanced_culler: FoveaInstancedCuller
var splat_mesh: ArrayMesh
var triangle_mesh_generator: GDScript
var _last_camera_pos: Vector3 = Vector3.ZERO
var _last_transforms: Array[Transform3D] = []
var _last_transforms_size: int = 0

var instance_colors: Array[Color] = []
var instance_scales: Array[float] = []
var instance_alphas: Array[float] = []
var instance_morph_types: Array[int] = []
var instance_morph_weights: Array[float] = []
var instance_morph_frequencies: Array[float] = []
var instance_morph_amplitudes: Array[float] = []
var instance_delta_colors: Array[Dictionary] = []
var instance_delta_positions: Array[Dictionary] = []
var instance_delta_weights: Array[float] = []

var _last_colors: Array[Color] = []
var _last_scales: Array[float] = []
var _last_alphas: Array[float] = []
var _last_morph_types: Array[int] = []
var _last_morph_weights: Array[float] = []
var _last_morph_frequencies: Array[float] = []
var _last_morph_amplitudes: Array[float] = []
var _last_delta_colors_hashes: Array[int] = []
var _last_delta_positions_hashes: Array[int] = []
var _last_delta_weights: Array[float] = []

var _cached_main_light: DirectionalLight3D = null
var delta_manager: RefCounted = null
var _cached_fovea_asset: FoveaAsset = null
var _cached_fovea_asset_path: String = ""

func _ready() -> void:
	instanced_culler = FoveaInstancedCuller.new()
	delta_manager = preload("res://addons/foveacore/scripts/advanced/fovea_delta_manager.gd").new()
	triangle_mesh_generator = load("res://addons/foveacore/scripts/advanced/triangle_splat_mesh.gd")

	# 1. Création de la géométrie de base (Maillage TRIANGLE)
	if use_triangle_mesh:
		splat_mesh = triangle_mesh_generator.generate_triangle_splat_mesh_optimized()
	else:
		# Fallback: QuadMesh classique
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

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = splat_mesh

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
	material.set_shader_parameter("splat_subdivisions", splat_subdivisions)
	material.set_shader_parameter("use_palette", false)
	material.set_shader_parameter("palette_size", 0)
	material.set_shader_parameter("covar_scale_is_linear", true)
	self.material_override = material

	_set_default_covar_texture()

	if asset_path != "":
		load_and_render_splats()
		update_material_shader()
		if enable_palette:
			load_palette_from_fovea()
		call_deferred("_upload_covar_codebook")

func _process(_delta: float) -> void:
	if delta_manager:
		delta_manager.process_interpolation(_delta)
	var camera := get_viewport().get_camera_3d()
	if camera == null or material_override == null:
		return

	# 0. Mettre à jour la liste des transforms et overrides d'instances depuis le groupe "splattables"
	var active_nodes: Array[Node] = get_tree().get_nodes_in_group("splattables")
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var scales: Array[float] = []
	var alphas: Array[float] = []
	var morph_types: Array[int] = []
	var morph_weights: Array[float] = []
	var morph_frequencies: Array[float] = []
	var morph_amplitudes: Array[float] = []
	var delta_colors: Array[Dictionary] = []
	var delta_positions: Array[Dictionary] = []
	var delta_weights: Array[float] = []
	var delta_colors_hashes: Array[int] = []
	var delta_positions_hashes: Array[int] = []
	
	for n in active_nodes:
		if n is FoveaSplattable and n.splat_file_path == asset_path and n.visible and n.splatting_enabled:
			transforms.append(n.global_transform)
			colors.append(n.color_override)
			scales.append(n.scale_override)
			alphas.append(n.alpha_override)
			
			var m_idx := 0
			match n.morph_type:
				"None": m_idx = 0
				"Bend": m_idx = 1
				"Twist": m_idx = 2
				"Squish": m_idx = 3
				"Wave": m_idx = 4
			morph_types.append(m_idx)
			morph_weights.append(n.morph_weight)
			morph_frequencies.append(n.morph_frequency)
			morph_amplitudes.append(n.morph_amplitude)
			
			delta_colors.append(n.delta_colors)
			delta_positions.append(n.delta_positions)
			delta_weights.append(n.delta_weight)
			delta_colors_hashes.append(n.delta_colors.hash())
			delta_positions_hashes.append(n.delta_positions.hash())

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
			if i < _last_morph_types.size():
				if morph_types[i] != _last_morph_types[i]:
					changed = true
					break
				if not is_equal_approx(morph_weights[i], _last_morph_weights[i]):
					changed = true
					break
				if not is_equal_approx(morph_frequencies[i], _last_morph_frequencies[i]):
					changed = true
					break
				if not is_equal_approx(morph_amplitudes[i], _last_morph_amplitudes[i]):
					changed = true
					break
			else:
				changed = true
				break
			if i < _last_delta_colors_hashes.size():
				if delta_colors_hashes[i] != _last_delta_colors_hashes[i] or delta_positions_hashes[i] != _last_delta_positions_hashes[i]:
					changed = true
					break
				if i < _last_delta_weights.size() and not is_equal_approx(delta_weights[i], _last_delta_weights[i]):
					changed = true
					break
			else:
				changed = true
				break

	instance_transforms = transforms
	instance_colors = colors
	instance_scales = scales
	instance_alphas = alphas
	instance_morph_types = morph_types
	instance_morph_weights = morph_weights
	instance_morph_frequencies = morph_frequencies
	instance_morph_amplitudes = morph_amplitudes
	instance_delta_colors = delta_colors
	instance_delta_positions = delta_positions
	instance_delta_weights = delta_weights

	_last_transforms = transforms.duplicate()
	_last_colors = colors.duplicate()
	_last_scales = scales.duplicate()
	_last_alphas = alphas.duplicate()
	_last_morph_types = morph_types.duplicate()
	_last_morph_weights = morph_weights.duplicate()
	_last_morph_frequencies = morph_frequencies.duplicate()
	_last_morph_amplitudes = morph_amplitudes.duplicate()
	_last_delta_colors_hashes = delta_colors_hashes.duplicate()
	_last_delta_positions_hashes = delta_positions_hashes.duplicate()
	_last_delta_weights = delta_weights.duplicate()
	_last_transforms_size = transforms.size()

	# Recalculer le culling si la caméra bouge ou si les instances ont changé
	var cam_pos: Vector3 = camera.global_position
	
	# Update light direction in shader for dynamic specular calculations
	var mat := material_override as ShaderMaterial
	if mat:
		var main_light: DirectionalLight3D = _find_main_light()
		if main_light:
			var light_dir: Vector3 = -main_light.global_transform.basis.z.normalized()
			mat.set_shader_parameter("light_direction", light_dir)
			
	if changed or (cam_pos - _last_camera_pos).length() > sort_distance_threshold:
		_last_camera_pos = cam_pos
		load_and_render_splats()

func load_and_render_splats() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not instanced_culler:
		return

	if asset_path == "" or not FileAccess.file_exists(asset_path):
		return

	# 1. Load the canonical asset locally. The Rust fast path uses std::fs and may
	# not resolve Godot res:// paths, so its empty result must not discard palette,
	# covariance, or AABB sections that the GDScript loader can read.
	var canonical_asset: FoveaAsset = _load_canonical_fovea_asset()

	# 2. Charger les octets bruts du fichier .fovea
	var raw_bytes := PackedByteArray()
	if ClassDB.class_exists("FoveaAssetLoader") and ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("load_raw_splat_bytes"):
			raw_bytes = loader.load_raw_splat_bytes(asset_path)
	if raw_bytes.is_empty() and canonical_asset != null:
		raw_bytes = canonical_asset.splats_raw_bytes

	if raw_bytes.is_empty():
		# Fallback direct
		var file := FileAccess.open(asset_path, FileAccess.READ)
		if file:
			var all_bytes: PackedByteArray = file.get_buffer(file.get_length())
			file.close()

			if all_bytes.size() >= 8 and all_bytes.slice(0, 8).get_string_from_ascii() == "FOVEA_3D":
				var version: int = all_bytes.decode_u32(8)
				var splat_count: int = all_bytes.decode_u32(12)
				var header_size: int = 72 if version >= 2 else 48
				if all_bytes.size() >= header_size:
					var color_k: int = all_bytes.decode_u32(16)
					var covar_k: int = all_bytes.decode_u32(20)
					var palette_size: int = color_k * 12
					var covar_size: int = covar_k * 32
					var splats_start: int = header_size + palette_size + covar_size
					var splats_end: int = splats_start + splat_count * FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE
					if splat_count > 0 and all_bytes.size() >= splats_end:
						raw_bytes = all_bytes.slice(splats_start, splats_end)
			elif all_bytes.size() >= 16:
				raw_bytes = all_bytes.slice(16)
			else:
				raw_bytes = all_bytes

	if raw_bytes.is_empty():
		push_error("FoveaInstancedSplatRenderer: Failed to load raw bytes from %s." % asset_path)
		return

	# 3. Récupérer l'AABB
	var aabb_min := Vector3(-5, -5, -5)
	var aabb_max := Vector3(5, 5, 5)
	if ClassDB.class_exists("FoveaAssetLoader") and ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("get_asset_aabb"):
			var aabb_val: Variant = loader.get_asset_aabb(asset_path)
			if aabb_val is AABB:
				var aabb: AABB = aabb_val
				if aabb.size.length_squared() > 0.001:
					aabb_min = aabb.position
					aabb_max = aabb.end
	if canonical_asset != null:
		var canonical_aabb: AABB = canonical_asset.get_aabb()
		if canonical_aabb.size.length_squared() > 0.001:
			aabb_min = canonical_aabb.position
			aabb_max = canonical_aabb.end

	var mat := material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("aabb_min", aabb_min)
		mat.set_shader_parameter("aabb_max", aabb_max)
		mat.set_shader_parameter("enable_layered_splatting", enable_layered_splatting)

	# 4. Récupérer la texture de profondeur de la caméra si possible
	var depth_tex: RID = RID()
	if camera.has_method("get_camera_attributes") and camera.get_camera_attributes():
		var attrs: Variant = camera.get_camera_attributes()
		if attrs.has_method("get_depth_texture"):
			depth_tex = attrs.get_depth_texture()
	elif "attributes" in camera and camera.attributes:
		var attrs: Variant = camera.attributes
		if attrs.has_method("get_depth_texture"):
			depth_tex = attrs.get_depth_texture()

	# 5. Build extended 24-byte runtime records. The deterministic CPU path is
	# the default; compute culling remains explicitly experimental.
	var output_buffer_rid: RID = RID()
	var surviving_splats_count: int = 0
	var active_instance_indices: Array = []
	var culled_bytes: PackedByteArray = PackedByteArray()
	var use_compute_culling: bool = enable_experimental_gpu_culling or enable_gpu_driven
	var cull_res: Dictionary = {}
	if use_compute_culling:
		if instanced_culler.rd == null:
			push_warning("FoveaInstancedSplatRenderer: compute culling requested without a RenderingDevice.")
			multimesh.instance_count = 0
			return
		cull_res = instanced_culler.process_instanced_splats_ext(
			raw_bytes,
			instance_transforms,
			camera,
			depth_tex,
			cull_threshold,
			aabb_min,
			aabb_max,
			instance_delta_positions,
			instance_delta_colors,
			instance_morph_types,
			instance_morph_weights,
			instance_morph_frequencies,
			instance_morph_amplitudes,
			enable_gpu_driven,
			use_gpu_instance_culling
		)
	else:
		active_instance_indices = _visible_instance_indices(camera, aabb_min, aabb_max, instance_transforms)
		culled_bytes = _build_cpu_passthrough_records(raw_bytes, active_instance_indices.size())
		surviving_splats_count = culled_bytes.size() / FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE

	if use_compute_culling and enable_gpu_driven:
		var out_rid: RID = cull_res.get("output_texture", RID())
		var cnt_rid: RID = cull_res.get("counter_texture", RID())
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
			
			multimesh.instance_count = instance_transforms.size() * (raw_bytes.size() / 16)
		return

	if use_compute_culling:
		output_buffer_rid = cull_res.get("buffer_rid", RID())
		surviving_splats_count = int(cull_res.get("count", 0))
		active_instance_indices = cull_res.get("active_instance_indices", []) as Array
		if not output_buffer_rid.is_valid() or surviving_splats_count == 0:
			if output_buffer_rid.is_valid():
				instanced_culler.rd.free_rid(output_buffer_rid)
			multimesh.instance_count = 0
			return
		if instanced_culler == null or instanced_culler.rd == null:
			push_error("FoveaInstancedSplatRenderer: instanced_culler or rd is null, skipping data readback.")
			multimesh.instance_count = 0
			return
		culled_bytes = instanced_culler.rd.buffer_get_data(output_buffer_rid)
		# Buffer capacity beyond the atomic count is unwritten, not splat data.
		culled_bytes.resize(surviving_splats_count * FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)

	if surviving_splats_count == 0:
		multimesh.instance_count = 0
		return

	# 6. Nettoyage GPU optionnel
	if enable_cleaning and surviving_splats_count > 0:
		var before_clean: int = surviving_splats_count
		culled_bytes = FoveaSplatCleaner.filter_nan_inf(culled_bytes, FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)
		culled_bytes = FoveaSplatCleaner.filter_floaters(
			culled_bytes, floater_neighbor_radius, floater_min_neighbors, FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)
		if enable_decimation and decimation_target > 0:
			culled_bytes = FoveaSplatCleaner.decimate(culled_bytes, decimation_target, FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)
		surviving_splats_count = culled_bytes.size() / FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE
		
	if enable_coplanar_merge and surviving_splats_count > 0:
		culled_bytes = FoveaSplatCleaner.merge_coplanar(
			culled_bytes, coplanar_z_bucket, 24, 1024, coplanar_min_group, FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)
		surviving_splats_count = culled_bytes.size() / FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE

	multimesh.instance_count = surviving_splats_count

	# Extraire les transforms et overrides correspondants aux instances visibles
	var active_transforms: Array[Transform3D] = []
	var active_colors: Array[Color] = []
	var active_scales: Array[float] = []
	var active_alphas: Array[float] = []
	var active_morph_types: Array[int] = []
	var active_morph_weights: Array[float] = []
	var active_morph_frequencies: Array[float] = []
	var active_morph_amplitudes: Array[float] = []
	var active_delta_colors: Array[Dictionary] = []
	var active_delta_positions: Array[Dictionary] = []
	var active_delta_weights: Array[float] = []
	
	for idx in active_instance_indices:
		active_transforms.append(instance_transforms[idx])
		active_colors.append(instance_colors[idx] if idx < instance_colors.size() else Color.WHITE)
		active_scales.append(instance_scales[idx] if idx < instance_scales.size() else 1.0)
		active_alphas.append(instance_alphas[idx] if idx < instance_alphas.size() else 1.0)
		active_morph_types.append(instance_morph_types[idx] if idx < instance_morph_types.size() else 0)
		active_morph_weights.append(instance_morph_weights[idx] if idx < instance_morph_weights.size() else 0.0)
		active_morph_frequencies.append(instance_morph_frequencies[idx] if idx < instance_morph_frequencies.size() else 1.0)
		active_morph_amplitudes.append(instance_morph_amplitudes[idx] if idx < instance_morph_amplitudes.size() else 0.5)
		active_delta_colors.append(instance_delta_colors[idx] if idx < instance_delta_colors.size() else {})
		active_delta_positions.append(instance_delta_positions[idx] if idx < instance_delta_positions.size() else {})
		active_delta_weights.append(instance_delta_weights[idx] if idx < instance_delta_weights.size() else 0.0)

	# 7. Décodage parallèle
	var decode_result := FoveaThreadPool.decode_parallel(
		culled_bytes,
		surviving_splats_count,
		aabb_min,
		aabb_max,
		active_transforms,
		active_colors,
		active_scales,
		active_alphas,
		active_morph_types,
		active_morph_weights,
		active_morph_frequencies,
		active_morph_amplitudes,
		active_delta_colors,
		active_delta_positions,
		active_delta_weights,
		FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE
	)

	multimesh.transform_array = decode_result.xf_array
	multimesh.custom_data_array = decode_result.cd_array

	# Libérer le buffer GPU
	if output_buffer_rid.is_valid():
		instanced_culler.rd.free_rid(output_buffer_rid)

static func _visible_instance_indices(
	camera: Camera3D,
	aabb_min: Vector3,
	aabb_max: Vector3,
	transforms: Array[Transform3D]
) -> Array[int]:
	var indices: Array[int] = []
	var frustum: FrustumUtils.Frustum = FrustumUtils.Frustum.new()
	frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)
	var local_aabb: AABB = AABB(aabb_min, aabb_max - aabb_min).grow(0.1)
	for index: int in range(transforms.size()):
		if frustum.contains_aabb(transforms[index] * local_aabb):
			indices.append(index)
	return indices

static func _build_cpu_passthrough_records(
	raw_bytes: PackedByteArray,
	active_instance_count: int
) -> PackedByteArray:
	var output: PackedByteArray = PackedByteArray()
	if raw_bytes.is_empty() or raw_bytes.size() % FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE != 0 or active_instance_count <= 0:
		return output
	var splat_count: int = raw_bytes.size() / FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE
	output.resize(splat_count * active_instance_count * FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)
	for instance_id: int in range(active_instance_count):
		for local_idx: int in range(splat_count):
			var source_offset: int = local_idx * FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE
			var target_record: int = instance_id * splat_count + local_idx
			var target_offset: int = target_record * FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE
			for byte_index: int in range(FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE):
				output[target_offset + byte_index] = raw_bytes[source_offset + byte_index]
			output.encode_u32(target_offset + FoveaInstancedSplatLayout.LOCAL_IDX_OFFSET, local_idx)
			output.encode_u32(target_offset + FoveaInstancedSplatLayout.INSTANCE_ID_OFFSET, instance_id)
	return output

func _load_canonical_fovea_asset() -> FoveaAsset:
	if _cached_fovea_asset != null and _cached_fovea_asset_path == asset_path:
		return _cached_fovea_asset
	_cached_fovea_asset = null
	_cached_fovea_asset_path = ""
	if asset_path.is_empty() or not FileAccess.file_exists(asset_path):
		return null
	var loader := FoveaAssetFormatLoaderScript.new()
	var loaded: Variant = loader._load(
		asset_path,
		asset_path,
		false,
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if loaded is FoveaAsset:
		_cached_fovea_asset = loaded as FoveaAsset
		_cached_fovea_asset_path = asset_path
	return _cached_fovea_asset

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
	if ClassDB.class_exists("FoveaAssetLoader") and ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("load_covariance_codebook"):
			codebook_bytes = loader.load_covariance_codebook(asset_path)
	if codebook_bytes.is_empty():
		var canonical_asset: FoveaAsset = _load_canonical_fovea_asset()
		if canonical_asset != null:
			codebook_bytes = canonical_asset.covariance_codebook

	if codebook_bytes.is_empty():
		return

	var entry_size: int = FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE
	if codebook_bytes.size() % entry_size != 0:
		push_error("FoveaInstancedSplatRenderer: Covariance codebook is not 32-byte aligned.")
		return
	var k: int = codebook_bytes.size() / entry_size
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
	var palette: FoveaColorPalette = null
	if ClassDB.class_exists("FoveaAssetLoader") and ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("load_color_palette"):
			var palette_bytes: PackedByteArray = loader.load_color_palette(asset_path)
			if palette_bytes.size() >= 12 and palette_bytes.size() % 12 == 0:
				var palette_colors: int = palette_bytes.size() / 12
				palette = FoveaColorPalette.new()
				palette.palette_name = asset_path.get_file() + " palette"
				palette.palette_size = palette_colors
				palette.colors.resize(palette_colors)
				for i: int in palette_colors:
					palette.colors[i] = Color(
						palette_bytes.decode_float(i * 12),
						palette_bytes.decode_float(i * 12 + 4),
						palette_bytes.decode_float(i * 12 + 8)
					)
	if palette == null:
		var canonical_asset: FoveaAsset = _load_canonical_fovea_asset()
		if canonical_asset != null:
			palette = canonical_asset.color_palette
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
	material.set_shader_parameter("use_palette", true)
	material.set_shader_parameter("palette_texture", tex)
	material.set_shader_parameter("palette_size", palette.colors.size())

func _has_color_palette() -> bool:
	var canonical_asset: FoveaAsset = _load_canonical_fovea_asset()
	return canonical_asset != null and canonical_asset.color_palette != null and not canonical_asset.color_palette.colors.is_empty()

func update_material_shader() -> void:
	var mat := material_override as ShaderMaterial
	if not mat:
		return
	
	if mat.shader and mat.shader.resource_path.ends_with("splat_render_artistic.gdshader"):
		TexturedSplatGenerator.apply_brush_textures(mat)
		return
		
	var has_palette: bool = _has_color_palette() if enable_palette else false
	if enable_palette and ClassDB.class_exists("FoveaAssetLoader") and ClassDB.can_instantiate("FoveaAssetLoader") and asset_path != "":
		var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("load_color_palette"):
			var palette_bytes: PackedByteArray = loader.load_color_palette(asset_path)
			has_palette = has_palette or not palette_bytes.is_empty()
	if has_palette and use_dithering:
		mat.shader = preload("res://addons/foveacore/shaders/splat_render_triangle_palette.gdshader")
		mat.set_shader_parameter("use_dithering", true)
		mat.set_shader_parameter("dither_strength", dither_strength)
	else:
		mat.shader = preload("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
		mat.set_shader_parameter("use_palette", has_palette)
	mat.set_shader_parameter("covar_scale_is_linear", true)

func _exit_tree() -> void:
	if instanced_culler:
		instanced_culler.cleanup()

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
