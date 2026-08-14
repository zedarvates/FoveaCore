extends SceneTree

const HLOD_GENERATOR := preload("res://addons/foveacore/scripts/advanced/fovea_hlod_generator.gd")
const GAUSSIAN_SPLAT := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_empty_input()
	_test_spatial_grouping_and_weighted_color()
	_test_invalid_cell_size_keeps_original_level()
	print("HLOD generator: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_empty_input() -> void:
	var empty_splats: Array[GaussianSplat] = []
	var levels: Dictionary = HLOD_GENERATOR.generate_hlod_levels(empty_splats, [0.2, 0.8, 3.0])
	_expect("empty input creates all requested levels", levels.size() == 4)
	for level_id: int in range(4):
		var level: Array = levels.get(level_id, [])
		_expect("empty level %d stays empty" % level_id, level.is_empty())


func _test_spatial_grouping_and_weighted_color() -> void:
	var red: GaussianSplat = GAUSSIAN_SPLAT.new(Vector3(0.10, 0.0, 0.0))
	red.color = Color.RED
	red.opacity = 1.0
	red.scale = Vector3(0.1, 0.1, 0.02)

	var blue: GaussianSplat = GAUSSIAN_SPLAT.new(Vector3(0.20, 0.0, 0.0))
	blue.color = Color.BLUE
	blue.opacity = 0.5
	blue.scale = Vector3(0.1, 0.1, 0.02)

	var distant: GaussianSplat = GAUSSIAN_SPLAT.new(Vector3(1.20, 0.0, 0.0))
	distant.color = Color.GREEN
	distant.opacity = 1.0
	distant.scale = Vector3(0.1, 0.1, 0.02)

	var originals: Array[GaussianSplat] = [red, blue, distant]
	var levels: Dictionary = HLOD_GENERATOR.generate_hlod_levels(originals, [1.0])
	var lod_1: Array[GaussianSplat] = levels[1]
	_expect("one-metre grid merges only colocated splats", lod_1.size() == 2)

	var merged: GaussianSplat = lod_1[0]
	_expect("merged position is the source centroid", merged.position.is_equal_approx(Vector3(0.15, 0.0, 0.0)))
	_expect("merged red channel is opacity weighted", is_equal_approx(merged.color.r, 2.0 / 3.0))
	_expect("merged blue channel is opacity weighted", is_equal_approx(merged.color.b, 1.0 / 3.0))
	_expect("source splats remain unchanged", red.position == Vector3(0.10, 0.0, 0.0) and blue.color == Color.BLUE)


func _test_invalid_cell_size_keeps_original_level() -> void:
	var splat: GaussianSplat = GAUSSIAN_SPLAT.new(Vector3.ONE)
	var originals: Array[GaussianSplat] = [splat]
	var levels: Dictionary = HLOD_GENERATOR.generate_hlod_levels(originals, [0.0])
	var lod_1: Array[GaussianSplat] = levels[1]
	_expect("non-positive cell size keeps the original splats", lod_1.size() == 1 and lod_1[0] == splat)


func _expect(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		push_error("FAIL: " + label)
