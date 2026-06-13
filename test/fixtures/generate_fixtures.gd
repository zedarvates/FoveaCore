extends SceneTree
## generate_fixtures.gd — Deterministic reference fixtures for the FoveaEngine test suite.
##
## Produces, under res://test/fixtures/ :
##   - reference_3dgs.ply   : valid binary little-endian 3DGS point cloud (seeded, REPRODUCIBLE)
##   - reference_3dgs.fovea : golden compressed asset written from the same splats
##   - pathological_nan.ply : valid header but NaN/Inf values (parser robustness)
##   - truncated_header.ply : header cut off before end_header (parser robustness)
##   - MANIFEST.md          : documents counts, layout and intent
##
## Run:  godot --headless --path . -s res://test/fixtures/generate_fixtures.gd
## These outputs are committed; regenerate only when the format intentionally changes.
## See plans/PHASE0_FONDATION_TASKS.md (C2).

const GaussianSplat = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const FoveaAssetWriterScript = preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")

const FIXTURE_DIR := "res://test/fixtures"
const SPLAT_COUNT := 8000
const RNG_SEED := 1234567  # fixed seed → reproducible bytes

# Standard reduced-3DGS property layout (17 floats / 68 bytes per vertex).
const PROPS := [
	"x", "y", "z",
	"nx", "ny", "nz",
	"f_dc_0", "f_dc_1", "f_dc_2",
	"opacity",
	"scale_0", "scale_1", "scale_2",
	"rot_0", "rot_1", "rot_2", "rot_3",
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))

	var rows := _build_rows()
	_write_binary_ply(FIXTURE_DIR.path_join("reference_3dgs.ply"), rows)
	_write_golden_fovea(FIXTURE_DIR.path_join("reference_3dgs.fovea"), rows)
	_write_pathological_nan(FIXTURE_DIR.path_join("pathological_nan.ply"))
	_write_truncated_header(FIXTURE_DIR.path_join("truncated_header.ply"))
	_write_manifest(FIXTURE_DIR.path_join("MANIFEST.md"))

	print("Fixtures generated under %s (%d splats)." % [FIXTURE_DIR, SPLAT_COUNT])
	quit(0)


## Builds the raw per-vertex float rows (3DGS-native: log-scale, logit-opacity, SH f_dc).
func _build_rows() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var rows := []
	rows.resize(SPLAT_COUNT)
	for i in range(SPLAT_COUNT):
		# Position inside a 4x3x4 box (deterministic spread).
		var px := rng.randf_range(-2.0, 2.0)
		var py := rng.randf_range(-1.5, 1.5)
		var pz := rng.randf_range(-2.0, 2.0)
		# Normal (unit-ish), as exported by most tools (often near zero, here varied).
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		# Colour via SH degree-0 coefficients.
		var fdc0 := rng.randf_range(-1.5, 1.5)
		var fdc1 := rng.randf_range(-1.5, 1.5)
		var fdc2 := rng.randf_range(-1.5, 1.5)
		# Opacity as logit (loader applies sigmoid → ~[0.12, 0.98]).
		var op := rng.randf_range(-2.0, 4.0)
		# Scale in log space (loader applies exp → small splats).
		var s0 := rng.randf_range(-5.0, -2.0)
		var s1 := rng.randf_range(-5.0, -2.0)
		var s2 := rng.randf_range(-5.0, -2.0)
		# Rotation quaternion (w, x, y, z), normalized.
		var q := Quaternion(
			rng.randf_range(-1, 1), rng.randf_range(-1, 1),
			rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		rows[i] = [
			px, py, pz,
			n.x, n.y, n.z,
			fdc0, fdc1, fdc2,
			op,
			s0, s1, s2,
			q.w, q.x, q.y, q.z,
		]
	return rows


func _ply_header(count: int) -> String:
	var h := "ply\nformat binary_little_endian 1.0\nelement vertex %d\n" % count
	for p in PROPS:
		h += "property float %s\n" % p
	h += "end_header\n"
	return h


func _write_binary_ply(path: String, rows: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_ply_header(rows.size()))
	for row in rows:
		for v in row:
			f.store_float(v)
	f.close()
	print("  wrote %s (%d verts)" % [path, rows.size()])


func _write_golden_fovea(path: String, rows: Array) -> void:
	var splats: Array[GaussianSplat] = []
	splats.resize(rows.size())
	for i in range(rows.size()):
		var r = rows[i]
		var s := GaussianSplat.new(Vector3(r[0], r[1], r[2]))
		s.normal = Vector3(r[3], r[4], r[5])
		s.surface_normal = s.normal
		s.color = Color(
			clampf(0.5 + 0.28209 * r[6], 0.0, 1.0),
			clampf(0.5 + 0.28209 * r[7], 0.0, 1.0),
			clampf(0.5 + 0.28209 * r[8], 0.0, 1.0))
		s.opacity = 1.0 / (1.0 + exp(-r[9]))
		s.color.a = s.opacity
		s.scale = Vector3(exp(r[10]), exp(r[11]), exp(r[12]))
		s.rotation = Quaternion(r[14], r[15], r[16], r[13]).normalized()
		s.compute_derived()
		splats[i] = s
	var ok: bool = FoveaAssetWriterScript.write_fovea_asset(path, splats, null, null, {
		"fixture": "reference_3dgs",
		"generator": "test/fixtures/generate_fixtures.gd",
		"splat_count": rows.size(),
	})
	print("  wrote %s (golden, ok=%s)" % [path, ok])


## Valid header, but the first few vertices carry NaN/Inf to exercise sanitization.
func _write_pathological_nan(path: String) -> void:
	var count := 64
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_ply_header(count))
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED + 1
	for i in range(count):
		for j in range(PROPS.size()):
			var v := rng.randf_range(-1.0, 1.0)
			if i < 8:
				# Poison positions/scales of the first rows.
				if j == 0: v = NAN
				elif j == 2: v = INF
				elif j == 10: v = -INF
			f.store_float(v)
	f.close()
	print("  wrote %s (%d verts, poisoned)" % [path, count])


## Declares 100 vertices but stops mid-header (no end_header, no body).
func _write_truncated_header(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("ply\nformat binary_little_endian 1.0\nelement vertex 100\nproperty float x\nproperty float y\n")
	# Intentionally no 'end_header' and no vertex data.
	f.close()
	print("  wrote %s (truncated header)" % path)


func _write_manifest(path: String) -> void:
	var body := """# FoveaEngine test fixtures

Deterministic reference data for the test suite. Regenerate with:

    godot --headless --path . -s res://test/fixtures/generate_fixtures.gd

| File | Kind | Verts | Purpose |
|---|---|---|---|
| `reference_3dgs.ply` | binary LE 3DGS | %d | Happy-path parse + round-trip source |
| `reference_3dgs.fovea` | golden compressed | %d | Round-trip / regression baseline (C3) |
| `pathological_nan.ply` | binary LE 3DGS | 64 | NaN/Inf sanitization (first 8 rows poisoned) |
| `truncated_header.ply` | malformed | 0 | Header parser must fail gracefully |

Layout of the PLY vertices (17 × float32, little-endian):
`x y z  nx ny nz  f_dc_0 f_dc_1 f_dc_2  opacity  scale_0 scale_1 scale_2  rot_0 rot_1 rot_2 rot_3`

Values are 3DGS-native: opacity is a logit (sigmoid on load), scales are in log
space (exp on load), colour is SH degree-0 (`0.5 + 0.28209 * f_dc`). Seed = %d.
""" % [SPLAT_COUNT, SPLAT_COUNT, RNG_SEED]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()
	print("  wrote %s" % path)
