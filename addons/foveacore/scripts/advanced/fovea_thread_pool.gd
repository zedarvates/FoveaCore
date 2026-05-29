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
	var xf_array:  PackedFloat32Array = PackedFloat32Array()
	var cd_array:  PackedFloat32Array = PackedFloat32Array()
	var original_transforms: Array[Transform3D] = []
	var splat_count: int = 0

# ── API publique ─────────────────────────────────────────────────────────────

## Décode culled_bytes en parallel sur tous les cœurs CPU disponibles.
## @param culled_bytes  : PackedByteArray issue du compute shader
## @param num_splats    : nombre de splats valides dans le buffer
## @returns DecodeResult prêt pour injection dans MultiMesh
static func decode_parallel(culled_bytes: PackedByteArray, num_splats: int) -> DecodeResult:
	var result: DecodeResult = DecodeResult.new()
	result.splat_count = num_splats

	if num_splats == 0:
		return result

	# Pré-allouer les buffers finaux en une seule opération
	result.xf_array.resize(num_splats * TRANSFORM_FLOATS)
	result.cd_array.resize(num_splats * CUSTOM_FLOATS)
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
				result.original_transforms, 0, num_splats)
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

		thread.start(func() -> void:
			_decode_chunk(_culled, _xf, _cd, _orig, _start, _end)
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
		xf_array:             PackedFloat32Array,
		cd_array:             PackedFloat32Array,
		original_transforms:  Array[Transform3D],
		start:                int,
		end:                  int
) -> void:
	for i: int in range(start, end):
		var src: int = i * SPLAT_BYTE_SIZE

		# Décoder position quantisée 16-bit → float monde
		# Format FoveaPackedSplat: [u16 px][u16 py][u16 pz][u16 pad][u16 color][u16 covar][u8 opacity][u8 flags][u8 pad0][u8 pad1]
		var px: float = culled_bytes.decode_u16(src)     / 65535.0 * AABB_RANGE
		var py: float = culled_bytes.decode_u16(src + 2) / 65535.0 * AABB_RANGE
		var pz: float = culled_bytes.decode_u16(src + 4) / 65535.0 * AABB_RANGE

		# Remplir transform_array (translation pure, Basis = IDENTITY)
		# Layout row-major 3×4 : [m00 m01 m02 m03 | m10 m11 m12 m13 | m20 m21 m22 m23]
		var xf_off: int = i * TRANSFORM_FLOATS
		xf_array[xf_off]      = 1.0; xf_array[xf_off + 1]  = 0.0; xf_array[xf_off + 2]  = 0.0; xf_array[xf_off + 3]  = px
		xf_array[xf_off + 4]  = 0.0; xf_array[xf_off + 5]  = 1.0; xf_array[xf_off + 6]  = 0.0; xf_array[xf_off + 7]  = py
		xf_array[xf_off + 8]  = 0.0; xf_array[xf_off + 9]  = 0.0; xf_array[xf_off + 10] = 1.0; xf_array[xf_off + 11] = pz

		# Remplir custom_data_array
		var color_index: float = float(culled_bytes.decode_u16(src + 8))  / 65535.0
		var covar_index: float = float(culled_bytes.decode_u16(src + 10)) / 65535.0
		var opacity:     float = float(culled_bytes.decode_u8(src + 12))  / 255.0

		var cd_off: int = i * CUSTOM_FLOATS
		cd_array[cd_off]     = color_index
		cd_array[cd_off + 1] = covar_index
		cd_array[cd_off + 2] = opacity
		cd_array[cd_off + 3] = 1.0

		# Cache des originaux pour le FoveaClayDeformer (non-destructif)
		original_transforms[i] = Transform3D(Basis(), Vector3(px, py, pz))
