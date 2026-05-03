extends Node

## Unit tests for StyleEngine
## Validates procedural material computation: colors, roughness, specular, bump, noise functions

var _passed := 0
var _failed := 0
var _config: Object  # MaterialStyleConfig (inner class, created dynamically)

signal test_passed(test_name: String, details: String)
signal test_failed(test_name: String, error: String)
signal all_complete(passed: int, failed: int)


func _ready() -> void:
	print("\n" + "=".repeat(70))
	print("StyleEngine Unit Tests")
	print("=".repeat(70))

	_config = _make_config()

	await get_tree().create_timer(0.3).timeout
	_run_all()


func _make_config() -> Object:
	var cfg = StyleEngine.MaterialStyleConfig.new()
	cfg.base_color = Color(0.6, 0.5, 0.4)
	cfg.detail = 1.0
	cfg.grain = 0.5
	cfg.light_coherence = 0.8
	cfg.micro_shadow = 0.5
	cfg.specular_strength = 0.3
	cfg.bump_strength = 0.5
	cfg.noise_scale = 10.0
	cfg.noise_octaves = 4
	cfg.noise_lacunarity = 2.0
	cfg.noise_gain = 0.5
	return cfg


func _run_all() -> void:
	print("\n--- Color computation (all materials) ---")
	var pos := Vector3(1.0, 2.0, 3.0)
	var normal := Vector3(0, 1, 0)
	var light := Vector3(0, 1, 0.5).normalized()

	for mat in [
		["STONE", StyleEngine.MaterialType.STONE],
		["WOOD", StyleEngine.MaterialType.WOOD],
		["METAL", StyleEngine.MaterialType.METAL],
		["SKIN", StyleEngine.MaterialType.SKIN],
		["FABRIC", StyleEngine.MaterialType.FABRIC],
		["GLASS", StyleEngine.MaterialType.GLASS],
		["CUSTOM", StyleEngine.MaterialType.CUSTOM],
	]:
		var name: String = mat[0]
		var mt: int = mat[1]
		var c = StyleEngine.compute_color(pos, normal, mt, _config, light)
		_assert_valid_color("compute_color(%s)" % name, c)
		_assert_roughness_range("roughness(%s)" % name,
			StyleEngine.compute_roughness(pos, normal, mt, _config))

	print("\n--- Color determinism ---")
	var c1 = StyleEngine.compute_color(pos, normal, StyleEngine.MaterialType.STONE, _config, light)
	var c2 = StyleEngine.compute_color(pos, normal, StyleEngine.MaterialType.STONE, _config, light)
	_assert_eq("Deterministic STONE color", c1, c2)

	print("\n--- Roughness ranges ---")
	_assert_range("roughness(STONE)", StyleEngine.compute_roughness(pos, normal, StyleEngine.MaterialType.STONE, _config), 0.0, 1.0)
	_assert_range("roughness(WOOD)", StyleEngine.compute_roughness(pos, normal, StyleEngine.MaterialType.WOOD, _config), 0.0, 1.0)
	_assert_range("roughness(METAL)", StyleEngine.compute_roughness(pos, normal, StyleEngine.MaterialType.METAL, _config), 0.0, 0.5)
	_assert_range("roughness(SKIN)", StyleEngine.compute_roughness(pos, normal, StyleEngine.MaterialType.SKIN, _config), 0.0, 1.0)
	_assert_range("roughness(GLASS)", StyleEngine.compute_roughness(pos, normal, StyleEngine.MaterialType.GLASS, _config), 0.04, 0.06)
	_assert_range("roughness(FABRIC)", StyleEngine.compute_roughness(pos, normal, StyleEngine.MaterialType.FABRIC, _config), 0.0, 1.0)

	print("\n--- Specular ---")
	var view := Vector3(0, 0, 1).normalized()
	var spec = StyleEngine.compute_specular(pos, normal, view, light, StyleEngine.MaterialType.METAL, _config)
	_assert_range("specular(METAL)", spec, 0.0, 1.0)

	var spec_zero = StyleEngine.compute_specular(pos, Vector3(0, 0, -1), view, light, StyleEngine.MaterialType.METAL, _config)
	_assert_approx("specular(facing away)", spec_zero, 0.0, 0.01)

	print("\n--- Bump ---")
	var bump = StyleEngine.compute_bump(pos, normal, StyleEngine.MaterialType.STONE, _config)
	_assert_approx("bump normalized", bump.length(), 1.0, 0.01)
	_assert("bump perturbed from normal", bump != normal, "Bump should differ from input normal")

	print("\n--- Glass specifics ---")
	var glass_color = StyleEngine.compute_color(pos, normal, StyleEngine.MaterialType.GLASS, _config, light)
	_assert("Glass has alpha < 1.0", glass_color.a < 1.0, "Glass should be translucent")
	_assert("Glass has alpha > 0.0", glass_color.a > 0.0, "Glass should not be invisible")

	print("\n--- Noise functions ---")
	var n1 = StyleEngine._simple_noise(Vector3(1, 2, 3))
	var n2 = StyleEngine._simple_noise(Vector3(1, 2, 3))
	_assert_eq("_simple_noise deterministic", n1, n2)
	_assert_range("_simple_noise [0,1]", n1, 0.0, 1.0)

	var fbm_val = StyleEngine._fbm(pos, 4)
	_assert_range("_fbm [0,1]", fbm_val, 0.0, 1.0)

	var worley = StyleEngine._worley_noise(pos)
	_assert("_worley_noise >= 0", worley >= 0.0, "")

	print("\n--- Spatial variation ---")
	var p1 := Vector3(0, 0, 0)
	var p2 := Vector3(100, 100, 100)
	var c_near = StyleEngine.compute_color(p1, normal, StyleEngine.MaterialType.STONE, _config, light)
	var c_far = StyleEngine.compute_color(p2, normal, StyleEngine.MaterialType.STONE, _config, light)
	_assert("Spatial variation exists", c_near != c_far, "Distant positions should yield different colors")

	# Report
	print("\n" + "=".repeat(70))
	print("StyleEngine Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	all_complete.emit(_passed, _failed)


func _assert_valid_color(name: String, c: Color) -> void:
	var valid := (
		c.r >= 0.0 and c.r <= 1.0 and
		c.g >= 0.0 and c.g <= 1.0 and
		c.b >= 0.0 and c.b <= 1.0 and
		c.a >= 0.0 and c.a <= 1.0
	)
	if valid:
		_pass("%s = rgba(%.2f,%.2f,%.2f,%.2f)" % [name, c.r, c.g, c.b, c.a])
	else:
		_fail(name, "Color out of range: rgba(%f,%f,%f,%f)" % [c.r, c.g, c.b, c.a])


func _assert_roughness_range(name: String, r: float) -> void:
	_assert_range(name, r, 0.0, 1.0)


func _assert_range(name: String, val: float, lo: float, hi: float) -> void:
	if val >= lo and val <= hi:
		_pass("%s = %.4f ∈ [%.2f, %.2f]" % [name, val, lo, hi])
	else:
		_fail(name, "%.4f ∉ [%.2f, %.2f]" % [val, lo, hi])


func _assert_eq(name: String, a, b) -> void:
	if a == b:
		_pass(name)
	else:
		_fail(name, "%s != %s" % [str(a), str(b)])


func _assert_approx(name: String, val: float, target: float, tol: float) -> void:
	if abs(val - target) <= tol:
		_pass("%s = %.4f ≈ %.4f ±%.4f" % [name, val, target, tol])
	else:
		_fail(name, "%.4f ≠ %.4f ±%.4f" % [val, target, tol])


func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_pass(name if detail.is_empty() else "%s — %s" % [name, detail])
	else:
		_fail(name, detail)


func _pass(detail: String) -> void:
	_passed += 1
	print("  ✓ %s" % detail)
	test_passed.emit(detail, "")


func _fail(test_name: String, err: String) -> void:
	_failed += 1
	print("  ✗ %s — %s" % [test_name, err])
	test_failed.emit(test_name, err)
