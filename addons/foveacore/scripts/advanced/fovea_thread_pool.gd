class_name FoveaThreadPool
extends RefCounted

## FoveaEngine — FoveaThreadPool
## Décodeur parallèle multi-cœurs pour les Gaussian Splats.
##
## Architecture :
##   decode_parallel() découpe culled_bytes en N chunks égaux,
##   dispatche chaque chunk sur un Thread Godot 4,
##   puis fusionne les PackedFloat32Array partielles en deux buffers
##   finaux (transform_array + custom_data_array) prêts pour un
##   batch-write unique sur MultiMesh.
##
## Règles CLAUDE.md :
##   - Strictly Typed GDScript
##   - Aucun call bloquant dans _ready() (ce module est RefCounted)
##   - Batch writes uniquement : JAMAIS set_instance_transform()

## Taille d'un splat en bytes dans le format Fast-Path FoveaPackedSplat
const SPLAT_BYTE_SIZE: int = 16

## Nombre de floats par instance dans transform_array (matrice 3x4 row-major)
const TRANSFORM_FLOATS: int = 12

## Nombre de floats par instance dans custom_data_array (RGBA)
const CUSTOM_FLOATS: int = 4

## Domaine AABB pour la dé-quantisation (doit correspondre à GPUCullerPipeline)
const AABB_RANGE: float = 10.0

# ── Résultat d'un decode parallèle ──────────────────────────────────────────

class DecodeResult:
	var xf_array:  PackedVector3Array = PackedVector3Array()
	var cd_array:  PackedColorArray = PackedColorArray()
	var original_transforms: Array[Transform3D] = []
	var splat_count: int = 0

# ── API publique ─────────────────────────────────────────────────────────────

## Décode culled_bytes en parallel sur tous les cœurs CPU disponibles.
## @param culled_bytes  : PackedByteArray issue du compute shader
## @param num_splats    : nombre de splats valides dans le buffer
## @param aabb_min      : AABB min de l'asset
## @param aabb_max      : AABB max de l'asset
## @param instance_transforms : transforms des instances actives pour le positionnement / rotation
## @returns DecodeResult prêt pour injection dans MultiMesh
static func decode_parallel(
	culled_bytes: PackedByteArray,
	num_splats: int,
	aabb_min: Vector3,
	aabb_max: Vector3,
	instance_transforms: Array[Transform3D] = [],
	instance_colors: Array[Color] = [],
	instance_scales: Array[float] = [],
	instance_alphas: Array[float] = [],
	instance_morph_types: Array[int] = [],
	instance_morph_weights: Array[float] = [],
	instance_morph_frequencies: Array[float] = [],
	instance_morph_amplitudes: Array[float] = []
) -> DecodeResult:
	var result: DecodeResult = DecodeResult.new()
	result.splat_count = num_splats

	if num_splats == 0:
		return result

	# Pré-allouer les buffers finaux en une seule opération
	result.xf_array.resize(num_splats * 4)
	result.cd_array.resize(num_splats)
	result.original_transforms.resize(num_splats)

	# Déterminer le nombre de threads optimal
	var cpu_count: int = OS.get_processor_count()
	var thread_count: int = clampi(cpu_count, 1, 8)  # Plafonner à 8 threads

	# Éviter de spawner plus de threads que de splats
	if thread_count > num_splats:
		thread_count = num_splats

	# Pour les petits nuages, mono-thread est plus rapide (pas de surcharge)
	if num_splats < 4096 or thread_count <= 1:
		_decode_chunk(culled_bytes, result.xf_array, result.cd_array,
				result.original_transforms, 0, num_splats, aabb_min, aabb_max,
				instance_transforms, instance_colors, instance_scales, instance_alphas,
				instance_morph_types, instance_morph_weights, instance_morph_frequencies, instance_morph_amplitudes)
		return result

	# Découper en chunks et dispatcher
	var threads: Array[Thread] = []
	threads.resize(thread_count)

	var chunk_size: int = num_splats / thread_count
	var remainder:  int = num_splats % thread_count

	for t: int in range(thread_count):
		var start: int = t * chunk_size
		var end:   int = start + chunk_size
		if t == thread_count - 1:
			end += remainder  # Dernier thread prend le reste

		var thread: Thread = Thread.new()
		threads[t] = thread

		# Capturer les références par valeur pour chaque thread
		var _culled   := culled_bytes
		var _xf       := result.xf_array
		var _cd       := result.cd_array
		var _orig     := result.original_transforms
		var _start    := start
		var _end      := end
		var _min      := aabb_min
		var _max      := aabb_max
		var _inst_xf  := instance_transforms
		var _inst_col := instance_colors
		var _inst_scl := instance_scales
		var _inst_alp := instance_alphas
		var _inst_m_type := instance_morph_types
		var _inst_m_weight := instance_morph_weights
		var _inst_m_freq := instance_morph_frequencies
		var _inst_m_amp := instance_morph_amplitudes

		thread.start(func() -> void:
			_decode_chunk(_culled, _xf, _cd, _orig, _start, _end, _min, _max,
					_inst_xf, _inst_col, _inst_scl, _inst_alp,
					_inst_m_type, _inst_m_weight, _inst_m_freq, _inst_m_amp)
		)

	# Attendre tous les threads
	for t: int in range(thread_count):
		threads[t].wait_to_finish()

	return result

# ── Logique de décodage d'un chunk (exécutée par chaque thread) ──────────────

## Décode les splats [start, end[ de culled_bytes dans les buffers cibles.
## Cette fonction DOIT être sans effet de bord sur les ranges des autres threads.
static func _decode_chunk(
		culled_bytes:         PackedByteArray,
		xf_array:             PackedVector3Array,
		cd_array:             PackedColorArray,
		original_transforms:  Array[Transform3D],
		start:                int,
		end:                  int,
		aabb_min:             Vector3,
		aabb_max:             Vector3,
		instance_transforms:  Array[Transform3D] = [],
		instance_colors:      Array[Color] = [],
		instance_scales:      Array[float] = [],
		instance_alphas:      Array[float] = [],
		instance_morph_types: Array[int] = [],
		instance_morph_weights: Array[float] = [],
		instance_morph_frequencies: Array[float] = [],
		instance_morph_amplitudes: Array[float] = []
) -> void:
	var temp_buf := PackedByteArray()
	temp_buf.resize(4)

	for i: int in range(start, end):
		var src: int = i * SPLAT_BYTE_SIZE

		# Décoder position quantisée 16-bit → float monde (dé-quantisation spatiale via AABB réelle)
		var qx: float = float(culled_bytes.decode_u16(src))     / 65535.0
		var qy: float = float(culled_bytes.decode_u16(src + 2)) / 65535.0
		var qz: float = float(culled_bytes.decode_u16(src + 4)) / 65535.0

		var px: float = aabb_min.x + qx * (aabb_max.x - aabb_min.x)
		var py: float = aabb_min.y + qy * (aabb_max.y - aabb_min.y)
		var pz: float = aabb_min.z + qz * (aabb_max.z - aabb_min.z)

		var local_pos := Vector3(px, py, pz)
		var local_basis_x := Vector3.RIGHT
		var local_basis_y := Vector3.UP
		var local_basis_z := Vector3.BACK
		
		var instance_id: int = -1
		var morph_type: int = 0
		var morph_weight: float = 0.0
		var morph_freq: float = 1.0
		var morph_amp: float = 0.5

		if not instance_transforms.is_empty():
			# Lire l'instance_id taggé dans les 16 bits de poids fort de data3
			var data3: int = culled_bytes.decode_u32(src + 12)
			instance_id = (data3 >> 16) & 0xFFFF
			
			if instance_id >= 0 and instance_id < instance_morph_types.size():
				morph_type = instance_morph_types[instance_id]
				morph_weight = instance_morph_weights[instance_id]
				morph_freq = instance_morph_frequencies[instance_id]
				morph_amp = instance_morph_amplitudes[instance_id]

		# Appliquer le morphing local si configuré
		if morph_type > 0 and morph_weight > 0.0:
			match morph_type:
				1: # Bend
					var offset_x = sin(local_pos.y * morph_freq) * morph_amp * morph_weight
					local_pos.x += offset_x
					# Courbure d'orientation
					var angle = cos(local_pos.y * morph_freq) * morph_amp * morph_weight * morph_freq
					local_basis_y = local_basis_y.rotated(Vector3.FORWARD, angle)
					local_basis_x = local_basis_x.rotated(Vector3.FORWARD, angle)
				2: # Twist
					var angle = local_pos.y * morph_freq * morph_weight * morph_amp
					var cos_a = cos(angle)
					var sin_a = sin(angle)
					local_pos = Vector3(
						local_pos.x * cos_a - local_pos.z * sin_a,
						local_pos.y,
						local_pos.x * sin_a + local_pos.z * cos_a
					)
					local_basis_x = Vector3(cos_a, 0.0, sin_a)
					local_basis_z = Vector3(-sin_a, 0.0, cos_a)
				3: # Squish
					var factor_y = 1.0 - (morph_weight * morph_amp)
					var factor_xz = 1.0 + (morph_weight * morph_amp * 0.5)
					local_pos.y *= factor_y
					local_pos.x *= factor_xz
					local_pos.z *= factor_xz
					local_basis_y *= factor_y
					local_basis_x *= factor_xz
					local_basis_z *= factor_xz
				4: # Wave
					var wave_angle = (local_pos.x + local_pos.z) * morph_freq
					local_pos.y += sin(wave_angle) * morph_amp * morph_weight
					# Ne change pas la base, juste translation y

		var world_pos := local_pos
		var basis_x := local_basis_x
		var basis_y := local_basis_y
		var basis_z := local_basis_z

		if instance_id >= 0 and instance_id < instance_transforms.size():
			var xf_inst: Transform3D = instance_transforms[instance_id]
			world_pos = xf_inst * local_pos
			basis_x = xf_inst.basis * local_basis_x
			basis_y = xf_inst.basis * local_basis_y
			basis_z = xf_inst.basis * local_basis_z

		# Appliquer le multiplicateur d'échelle d'instance
		if instance_id >= 0 and instance_id < instance_scales.size():
			var scale_mult: float = instance_scales[instance_id]
			basis_x *= scale_mult
			basis_y *= scale_mult
			basis_z *= scale_mult

		# Remplir transform_array
		# Dans Godot 4.3+, MultiMesh.transform_array est un PackedVector3Array
		# Chaque transform est composé de 4 Vector3 : col0 (right/basis_x), col1 (up/basis_y), col2 (back/basis_z), col3 (origin/world_pos)
		var xf_off: int = i * 4
		xf_array[xf_off]      = basis_x
		xf_array[xf_off + 1]  = basis_y
		xf_array[xf_off + 2]  = basis_z
		xf_array[xf_off + 3]  = world_pos

		var w2: int = culled_bytes.decode_u32(src + 8)
		var w3: int = culled_bytes.decode_u32(src + 12)
		var w2_modified := false
		var w3_modified := false

		# Appliquer la teinte de couleur de l'instance (seulement si non-quantisé dans l'asset)
		if instance_id >= 0 and instance_id < instance_colors.size():
			var tint: Color = instance_colors[instance_id]
			if not is_equal_approx(tint.r, 1.0) or not is_equal_approx(tint.g, 1.0) or not is_equal_approx(tint.b, 1.0):
				var color_index := w2 & 0xFFFF
				var r_val := float((color_index >> 11) & 0x1F) / 31.0
				var g_val := float((color_index >> 5) & 0x3F) / 63.0
				var b_val := float(color_index & 0x1F) / 31.0
				
				var col := Color(r_val, g_val, b_val) * tint
				var r5 := int(clamp(col.r * 31.0, 0, 31))
				var g6 := int(clamp(col.g * 63.0, 0, 63))
				var b5 := int(clamp(col.b * 31.0, 0, 31))
				var new_rgb565 := (r5 << 11) | (g6 << 5) | b5
				
				w2 = (w2 & 0xFFFF0000) | new_rgb565
				w2_modified = true

		# Appliquer l'opacité / visibilité de l'instance
		if instance_id >= 0 and instance_id < instance_alphas.size():
			var alpha_mult: float = instance_alphas[instance_id]
			if not is_equal_approx(alpha_mult, 1.0):
				var op_val := float(w3 & 0xFF) / 255.0
				op_val *= alpha_mult
				var new_op := int(clamp(op_val * 255.0, 0, 255))
				w3 = (w3 & 0xFFFFFF00) | new_op
				w3_modified = true

		# Remplir custom_data_array avec les bits bruts des 4 mots de 32 bits (data0-data3)
		# Re-interprétés en floats via decode_float pour correspondre aux floatBitsToUint du Shader
		var r: float = culled_bytes.decode_float(src)
		var g: float = culled_bytes.decode_float(src + 4)
		var b: float
		var a: float

		if w2_modified:
			temp_buf.encode_u32(0, w2)
			b = temp_buf.decode_float(0)
		else:
			b = culled_bytes.decode_float(src + 8)

		if w3_modified:
			temp_buf.encode_u32(0, w3)
			a = temp_buf.decode_float(0)
		else:
			a = culled_bytes.decode_float(src + 12)

		cd_array[i] = Color(r, g, b, a)

		# Cache des originaux pour le FoveaClayDeformer (non-destructif)
		original_transforms[i] = Transform3D(Basis(basis_x, basis_y, basis_z), world_pos)
