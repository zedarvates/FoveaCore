extends SceneTree
## Tests for SplatFormatLoader — the .splat binary parser (Phase 1, J1).
## Writes a deterministic .splat, loads it back, and asserts round-trip fidelity
## plus robustness on corrupt/unsupported input. Non-GPU group.

const Loader := preload("res://addons/foveacore/scripts/reconstruction/splat_format_loader.gd")

const N := 256
var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("SplatFormatLoader (.splat) Tests — J1")
	print("=".repeat(70))

	await create_timer(0.1).timeout

	var path := "user://_test_fixture.splat"
	var expected := _write_splat(path)

	# Happy path via the unified router.
	var splats: Array = Loader.load_gaussians(path)
	_assert("router loads .splat", splats.size() == N, "%d == %d" % [splats.size(), N])

	if splats.size() == N:
		# Position is float32 → exact round-trip.
		var s0 = splats[0]
		_assert("position round-trips", s0.position.is_equal_approx(expected["pos0"]), "%s ~ %s" % [s0.position, expected["pos0"]])
		# Color is uint8 → within 1/255.
		var dc: float = absf(s0.color.r - expected["col0"].r) + absf(s0.color.g - expected["col0"].g) + absf(s0.color.b - expected["col0"].b)
		_assert("color round-trips (<3/255)", dc < 3.0 / 255.0, "Δ=%.4f" % dc)
		_assert("opacity round-trips", absf(s0.opacity - expected["op0"]) < 2.0 / 255.0, "%.3f ~ %.3f" % [s0.opacity, expected["op0"]])
		# Scale is absolute float32 → exact.
		_assert("scale round-trips", s0.scale.is_equal_approx(expected["scl0"]), "%s ~ %s" % [s0.scale, expected["scl0"]])
		# Rotation normalized & finite.
		_assert("rotation normalized", absf(s0.rotation.length() - 1.0) < 0.01, str(s0.rotation.length()))

		# AABB finite and non-degenerate.
		var aabb := _aabb(splats)
		_assert("AABB finite", _finite(aabb.position) and _finite(aabb.size), str(aabb))
		_assert("AABB non-degenerate", aabb.size.length_squared() > 0.001, str(aabb.size))

	# Robustness: truncated/corrupt file (size not a multiple of 32) → empty, no crash.
	var bad := "user://_test_bad.splat"
	var bf := FileAccess.open(bad, FileAccess.WRITE)
	bf.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))  # 5 bytes, not %32
	bf.close()
	_assert("corrupt .splat → empty (no crash)", Loader.load_splat(bad).is_empty(), "")

	# Robustness: missing file → empty.
	_assert("missing .splat → empty", Loader.load_splat("user://_does_not_exist.splat").is_empty(), "")

	# Routing: unsupported extension → empty; is_supported() correct.
	_assert("unsupported ext → empty", Loader.load_gaussians("foo.obj").is_empty(), "")
	_assert("is_supported(.splat)", Loader.is_supported("a.splat"), "")
	_assert("is_supported(.spz)", Loader.is_supported("a.spz"), "")
	_assert("not is_supported(.obj)", not Loader.is_supported("a.obj"), "")

	print("\n" + "=".repeat(70))
	print("SplatFormatLoader Tests: %d passed, %d failed" % [_passed, _failed])
	print("=".repeat(70))
	quit(1 if _failed > 0 else 0)


## Writes N deterministic 32-byte splats; returns the expected values of splat 0.
func _write_splat(path: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var f := FileAccess.open(path, FileAccess.WRITE)
	var first := {}
	for i in range(N):
		var pos := Vector3(rng.randf_range(-2, 2), rng.randf_range(-1, 1), rng.randf_range(-2, 2))
		var scl := Vector3(rng.randf_range(0.01, 0.2), rng.randf_range(0.01, 0.2), rng.randf_range(0.01, 0.2))
		var cr := rng.randi_range(0, 255)
		var cg := rng.randi_range(0, 255)
		var cb := rng.randi_range(0, 255)
		var ca := rng.randi_range(0, 255)
		var rb := PackedByteArray([rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255)])
		f.store_float(pos.x); f.store_float(pos.y); f.store_float(pos.z)
		f.store_float(scl.x); f.store_float(scl.y); f.store_float(scl.z)
		f.store_8(cr); f.store_8(cg); f.store_8(cb); f.store_8(ca)
		f.store_8(rb[0]); f.store_8(rb[1]); f.store_8(rb[2]); f.store_8(rb[3])
		if i == 0:
			first = {
				"pos0": pos, "scl0": scl,
				"col0": Color(cr / 255.0, cg / 255.0, cb / 255.0),
				"op0": ca / 255.0,
			}
	f.close()
	return first


func _aabb(splats: Array) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for s in splats:
		mn = mn.min(s.position)
		mx = mx.max(s.position)
	return AABB(mn, mx - mn)

func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _assert(name: String, cond: bool, detail: String) -> void:
	if cond:
		_passed += 1
		print("  ✓ %s — %s" % [name, detail])
	else:
		_failed += 1
		print("  ✗ %s — %s" % [name, detail])
