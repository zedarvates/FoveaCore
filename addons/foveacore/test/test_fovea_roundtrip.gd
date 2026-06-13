extends SceneTree
## Round-trip & fixture-integrity tests (Phase 0, C3).
##
## Exercises the reference fixtures under res://test/fixtures/ :
##   - reference_3dgs.ply   parses to the expected splat count with a finite AABB
##   - reference_3dgs.fovea (golden) loads and matches the PLY bounds
##   - PLY → splats → .fovea → reload preserves count and bounds (the real round-trip)
##   - pathological_nan.ply  does not crash the loader
##   - truncated_header.ply  returns gracefully (no infinite loop / hang)
##
## Non-GPU: pure parsing/serialization logic → runs in the hard-fail CI group.

const PLYLoaderScript := preload("res://addons/foveacore/scripts/reconstruction/ply_loader.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const FoveaAssetWriterScript := preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")
const FoveaAssetFormatLoaderScript := preload("res://addons/foveacore/scripts/fovea_asset_loader.gd")

const FIXTURE_DIR := "res://test/fixtures"
const EXPECTED_SPLATS := 8000

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("Fovea Round-trip & Fixture Integrity Tests")
	print("=".repeat(70))

	await create_timer(0.2).timeout

	if not _fixtures_present():
		_assert("Fixtures present", false, "missing under %s — run test/fixtures/generate_fixtures.gd" % FIXTURE_DIR)
		_summarize()
		return

	var ply_splats := _test_reference_ply()
	var golden_aabb := _test_golden_fovea(ply_splats)
	_test_roundtrip_reexport(ply_splats, golden_aabb)
	_test_pathological_nan()
	_test_truncated_header()

	_summarize()


func _fixtures_present() -> bool:
	return FileAccess.file_exists(FIXTURE_DIR.path_join("reference_3dgs.ply")) \
		and FileAccess.file_exists(FIXTURE_DIR.path_join("reference_3dgs.fovea")) \
		and FileAccess.file_exists(FIXTURE_DIR.path_join("pathological_nan.ply")) \
		and FileAccess.file_exists(FIXTURE_DIR.path_join("truncated_header.ply"))


## Returns the parsed splats so later tests can reuse them.
func _test_reference_ply() -> Array:
	print("\n--- reference_3dgs.ply ---")
	var splats: Array = PLYLoaderScript.load_gaussians_from_ply(FIXTURE_DIR.path_join("reference_3dgs.ply"))
	_assert("PLY splat count", splats.size() == EXPECTED_SPLATS, "%d == %d" % [splats.size(), EXPECTED_SPLATS])

	var aabb := _aabb_of(splats)
	var finite := _is_finite_vec(aabb.position) and _is_finite_vec(aabb.size)
	_assert("PLY AABB finite", finite, str(aabb))
	_assert("PLY AABB non-degenerate", aabb.size.length_squared() > 0.001, "size=%s" % aabb.size)
	# Positions were generated within a 4x3x4 box → sanity bound on extents.
	_assert("PLY AABB within expected bounds", aabb.size.x < 5.0 and aabb.size.y < 4.0 and aabb.size.z < 5.0, "size=%s" % aabb.size)
	return splats


## Returns the golden asset's AABB for the round-trip comparison.
func _test_golden_fovea(ply_splats: Array) -> AABB:
	print("\n--- reference_3dgs.fovea (golden) ---")
	var loader := FoveaAssetFormatLoaderScript.new()
	var res: Variant = loader._load(FIXTURE_DIR.path_join("reference_3dgs.fovea"), "", false, 0)
	_assert("Golden loads as Resource", res is Resource, str(res))
	if not (res is Resource):
		return AABB()

	_assert("Golden splat_count", res.splat_count == EXPECTED_SPLATS, "%d == %d" % [res.splat_count, EXPECTED_SPLATS])
	var gaabb := AABB(Vector3(res.aabb_min), Vector3(res.aabb_max) - Vector3(res.aabb_min))
	_assert("Golden AABB finite", _is_finite_vec(gaabb.position) and _is_finite_vec(gaabb.size), str(gaabb))

	# The writer adds a 0.01 safety margin, so the golden box must enclose the PLY box.
	var paabb := _aabb_of(ply_splats)
	var encloses := gaabb.encloses(paabb)
	_assert("Golden AABB encloses PLY AABB", encloses, "golden=%s ply=%s" % [gaabb, paabb])
	return gaabb


func _test_roundtrip_reexport(ply_splats: Array, golden_aabb: AABB) -> void:
	print("\n--- round-trip: PLY → .fovea → reload ---")
	var typed: Array[GaussianSplat] = []
	for s in ply_splats:
		typed.append(s as GaussianSplat)

	var tmp := "user://roundtrip_test.fovea"
	var ok: bool = FoveaAssetWriterScript.write_fovea_asset(tmp, typed, null, null, {"test": "roundtrip"})
	_assert("Re-export writes .fovea", ok, "write returned %s" % ok)

	var loader := FoveaAssetFormatLoaderScript.new()
	var res: Variant = loader._load(tmp, "", false, 0)
	_assert("Re-export reloads", res is Resource, str(res))
	if not (res is Resource):
		return
	_assert("Re-export splat_count preserved", res.splat_count == EXPECTED_SPLATS, "%d == %d" % [res.splat_count, EXPECTED_SPLATS])

	# Bounds should match the golden within the spatial quantization tolerance (16-bit over the AABB).
	var raabb := AABB(Vector3(res.aabb_min), Vector3(res.aabb_max) - Vector3(res.aabb_min))
	if golden_aabb.size.length_squared() > 0.0:
		var size_err := (raabb.size - golden_aabb.size).length() / golden_aabb.size.length()
		_assert("Re-export AABB size matches golden (<2%)", size_err < 0.02, "rel err=%.4f" % size_err)


func _test_pathological_nan() -> void:
	print("\n--- pathological_nan.ply (must not crash) ---")
	var splats: Array = PLYLoaderScript.load_gaussians_from_ply(FIXTURE_DIR.path_join("pathological_nan.ply"))
	# The fixture declares 64 vertices; the win is that the loader returns without crashing.
	_assert("Pathological PLY parsed without crash", splats.size() == 64, "got %d splats" % splats.size())
	var non_finite := 0
	for s in splats:
		if not _is_finite_vec(s.position):
			non_finite += 1
	# Informational: the bare loader does not sanitize NaN/Inf (a dedicated validator does).
	print("  ℹ %d/%d splats carry non-finite positions (sanitization is a separate pass)" % [non_finite, splats.size()])


func _test_truncated_header() -> void:
	print("\n--- truncated_header.ply (must not hang) ---")
	# Before the EOF guard in PLYLoader, this input spun forever. Reaching the
	# assertion at all proves the loop terminates.
	var splats: Array = PLYLoaderScript.load_gaussians_from_ply(FIXTURE_DIR.path_join("truncated_header.ply"))
	_assert("Truncated header returns gracefully", splats.is_empty(), "got %d splats" % splats.size())


# ── helpers ────────────────────────────────────────────────────────────────

func _aabb_of(splats: Array) -> AABB:
	if splats.is_empty():
		return AABB()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for s in splats:
		if _is_finite_vec(s.position):
			mn = mn.min(s.position)
			mx = mx.max(s.position)
	return AABB(mn, mx - mn)

func _is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s — %s" % [name, detail])
	else:
		_failed += 1
		print("  ✗ %s — %s" % [name, detail])

func _summarize() -> void:
	print("\n" + "=".repeat(70))
	print("Round-trip Tests: %d passed, %d failed" % [_passed, _failed])
	print("=".repeat(70))
	quit(1 if _failed > 0 else 0)
