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
## @returns DecodeResult prêt pour injection dans MultiMesh
static func decode_parallel(culled_bytes: PackedByteArray, num_splats: int, aabb_min: Vector3, aabb_max: Vector3) -> DecodeResult:
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
				result.original_transforms, 0, num_splats, aabb_min, aabb_max)
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

		thread.start(func() -> void:
			_decode_chunk(_culled, _xf, _cd, _orig, _start, _end, _min, _max)
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
		aabb_max:             Vector3
) -> void:
	for i: int in range(start, end):
		var src: int = i * SPLAT_BYTE_SIZE

		# Décoder position quantisée 16-bit → float monde (dé-quantisation spatiale via AABB réelle)
		var qx: float = float(culled_bytes.decode_u16(src))     / 65535.0
		var qy: float = float(culled_bytes.decode_u16(src + 2)) / 65535.0
		var qz: float = float(culled_bytes.decode_u16(src + 4)) / 65535.0

		var px: float = aabb_min.x + qx * (aabb_max.x - aabb_min.x)
		var py: float = aabb_min.y + qy * (aabb_max.y - aabb_min.y)
		var pz: float = aabb_min.z + qz * (aabb_max.z - aabb_min.z)

		# Remplir transform_array (translation pure, Basis = IDENTITY)
		# Dans Godot 4.3+, MultiMesh.transform_array est un PackedVector3Array
		# Chaque transform est composé de 4 Vector3 : col0 (right), col1 (up), col2 (back), col3 (origin)
		var xf_off: int = i * 4
		xf_array[xf_off]      = Vector3.RIGHT
		xf_array[xf_off + 1]  = Vector3.UP
		xf_array[xf_off + 2]  = Vector3.BACK
		xf_array[xf_off + 3]  = Vector3(px, py, pz)

		# Remplir custom_data_array avec les bits bruts des 4 mots de 32 bits (data0-data3)
		# Re-interprétés en floats via decode_float pour correspondre aux floatBitsToUint du Shader
		var r: float = culled_bytes.decode_float(src)
		var g: float = culled_bytes.decode_float(src + 4)
		var b: float = culled_bytes.decode_float(src + 8)
		var a: float = culled_bytes.decode_float(src + 12)
		cd_array[i] = Color(r, g, b, a)

		# Cache des originaux pour le FoveaClayDeformer (non-destructif)
		original_transforms[i] = Transform3D(Basis(), Vector3(px, py, pz))
