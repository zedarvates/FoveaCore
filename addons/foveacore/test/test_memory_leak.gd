extends SceneTree
## Asset lifecycle smoke test: load/release a small .fovea asset 100× (item 315).
## This is not native or VRAM leak certification; that requires external instrumentation.

const FoveaAssetFormatLoaderScript := preload("res://addons/foveacore/scripts/fovea_asset_loader.gd")
const FIXTURE_PATH := "res://test/fixtures/rust_v2_fixture.fovea"

var _passed := 0; var _failed := 0

func _init() -> void:
	print("\n=== Asset Lifecycle Smoke Test (item 315) ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)

func _run_all() -> void:
	if not FileAccess.file_exists(FIXTURE_PATH):
		_fail("Rust v2 fixture is available")
		return

	var successful_loads := 0
	for i in range(100):
		var loader := FoveaAssetFormatLoaderScript.new()
		var loaded: Variant = loader._load(FIXTURE_PATH, FIXTURE_PATH, false, 0)
		if loaded is FoveaAsset and loaded.splat_count == 1:
			successful_loads += 1
		loaded = null
		if i % 20 == 0:
			print("  Pass %d/100..." % (i + 1))
	_assert("100 load/release cycles preserve the canonical fixture", successful_loads == 100)
	print("  %d/%d" % [_passed, _passed + _failed])

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_fail(name)

func _fail(name: String) -> void:
	_failed += 1
	push_error("  ✗ %s" % name)
