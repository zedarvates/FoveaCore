extends SceneTree

const REQUIRES_GPU := true
const TEST_SPLAT_COUNTS: Array[int] = [3, 8, 256, 257, 1024, 17013, 25674]
const PERMUTATION_STRIDE := 37

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\n=== GPU Splat Sorter Tests ===")
	await create_timer(0.2).timeout
	_run_tests()
	quit(1 if _failed > 0 else 0)

func _run_tests() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.global_transform = Transform3D.IDENTITY

	for splat_count: int in TEST_SPLAT_COUNTS:
		_run_case(splat_count, camera)

	camera.queue_free()
	print("GPU splat sorter: %d passed, %d failed" % [_passed, _failed])

func _run_case(splat_count: int, camera: Camera3D) -> void:
	var splats: Array[GaussianSplat] = []
	splats.resize(splat_count)
	for index: int in range(splat_count):
		var depth_rank: int = (index * PERMUTATION_STRIDE) % splat_count
		var splat := GaussianSplat.new()
		splat.position = Vector3(float(index % 31) * 0.001, 0.0, -float(depth_rank + 1))
		splats[index] = splat

	var sorter := SplatSorter.new()
	sorter.debug_verbose = true
	_assert("Local GPU sorter initializes (%d splats)" % splat_count, sorter.is_gpu_available(), sorter.get_last_gpu_error())
	if sorter.is_gpu_available():
		var indices: Array[int] = sorter.sort_splats_back_to_front(splats, camera)
		_assert("Sort stays on the GPU (%d splats)" % splat_count, sorter.get_last_sort_backend() == &"gpu", sorter.get_last_gpu_error())
		_assert("GPU returns a complete permutation (%d splats)" % splat_count, indices.size() == splat_count, "received %d indices" % indices.size())
		_assert("Permutation is unique and in range (%d splats)" % splat_count, _is_complete_permutation(indices, splat_count), "duplicate or invalid index")
		_assert("The permutation is strictly back-to-front", _is_back_to_front(indices, splats), "view-space depth order is not descending")

	sorter._cleanup_gpu()

func _is_complete_permutation(indices: Array[int], splat_count: int) -> bool:
	if indices.size() != splat_count:
		return false
	var seen := PackedByteArray()
	seen.resize(splat_count)
	for index: int in indices:
		if index < 0 or index >= splat_count or seen[index] != 0:
			return false
		seen[index] = 1
	return true

func _is_back_to_front(indices: Array[int], splats: Array[GaussianSplat]) -> bool:
	var previous_depth: float = INF
	for index: int in indices:
		var depth: float = -splats[index].position.z
		if depth >= previous_depth:
			return false
		previous_depth = depth
	return true

func _assert(name: String, condition: bool, details: String = "") -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % name)
	else:
		_failed += 1
		push_error("  [FAIL] %s%s" % [name, " — " + details if not details.is_empty() else ""])
