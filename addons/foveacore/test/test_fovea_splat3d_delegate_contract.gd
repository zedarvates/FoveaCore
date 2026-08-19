extends SceneTree

## Non-GPU contract for the stable FoveaSplat3D node and its runtime-only
## FoveaSplattable delegate. Rendering quality remains a separate visual gate.

const FIXTURE_PATH: String = "res://addons/foveacore/test/fixtures/minimal_cli_fixture.ply"

var _passed: int = 0
var _failed: int = 0
var _loaded_paths: Array[String] = []

func _init() -> void:
	print("\nFoveaSplat3D Delegate Contract Tests")
	_assert("Minimal PLY fixture exists", FileAccess.file_exists(FIXTURE_PATH))
	if not FileAccess.file_exists(FIXTURE_PATH):
		_finish()
		return

	var splat: FoveaSplat3D = FoveaSplat3D.new()
	_assert("Delegate is absent before ready", splat.get_advanced() == null)
	splat.asset_loaded.connect(_on_asset_loaded)
	splat.source_path = FIXTURE_PATH
	splat.enabled = false
	splat.quality_preset = FoveaSplat3D.QualityPreset.PERFORMANCE
	splat.generate_collisions = false
	splat.opacity = 0.42
	splat.is_static = false
	root.add_child(splat)

	for _frame: int in range(3):
		await process_frame

	var delegate: FoveaSplattable = splat.get_advanced()
	_assert("Delegate exists after ready", delegate != null)
	if delegate == null:
		splat.queue_free()
		_finish()
		return

	_test_runtime_ownership(splat, delegate)
	_test_initial_propagation(delegate)
	_test_live_controls(splat, delegate)

	splat.queue_free()
	await process_frame
	_finish()

func _test_runtime_ownership(splat: FoveaSplat3D, delegate: FoveaSplattable) -> void:
	_assert("Delegate has the stable internal name", delegate.name == "FoveaSplattableInternal")
	_assert("Delegate is parented under the public node", delegate.get_parent() == splat)
	_assert("Delegate remains runtime-only", delegate.owner == null)
	_assert("Valid source emits one load signal", _loaded_paths == [FIXTURE_PATH])
	_assert("Delegate loads the one-splat fixture", delegate.loaded_splats.size() == 1)

func _test_initial_propagation(delegate: FoveaSplattable) -> void:
	_assert("Source path propagates", delegate.splat_file_path == FIXTURE_PATH)
	_assert("Disabled state propagates", not delegate.splatting_enabled and not delegate.visible)
	_assert("Performance density propagates", is_equal_approx(delegate.splat_density, 0.5))
	_assert("Performance priority propagates", delegate.culling_priority == 3)
	_assert("Opacity propagates", is_equal_approx(delegate.alpha_override, 0.42))
	_assert("Static hint propagates", not delegate.is_static)
	_assert("Collision request propagates", not delegate.generate_collisions)

func _test_live_controls(splat: FoveaSplat3D, delegate: FoveaSplattable) -> void:
	splat.enabled = true
	_assert("Live enable reaches the delegate", delegate.splatting_enabled and delegate.visible)

	splat.opacity = 0.73
	_assert("Live opacity reaches the delegate", is_equal_approx(delegate.alpha_override, 0.73))
	splat.is_static = true
	_assert("Live static hint reaches the delegate", delegate.is_static)
	splat.generate_collisions = true
	_assert("Live collision request reaches the delegate", delegate.generate_collisions)

	splat.quality_preset = FoveaSplat3D.QualityPreset.BALANCED
	_assert("Balanced preset restores neutral density", is_equal_approx(delegate.splat_density, 1.0))
	_assert("Balanced preset restores standard priority", delegate.culling_priority == 5)
	splat.quality_preset = FoveaSplat3D.QualityPreset.CINEMATIC
	_assert("Cinematic preset raises density", is_equal_approx(delegate.splat_density, 2.0))
	_assert("Cinematic preset raises priority", delegate.culling_priority == 9)
	splat.quality_preset = FoveaSplat3D.QualityPreset.AUTO
	_assert("Auto resets local density after an explicit preset", is_equal_approx(delegate.splat_density, 1.0))
	_assert("Auto resets local priority after an explicit preset", delegate.culling_priority == 5)

	var signal_count: int = _loaded_paths.size()
	splat.source_path = FIXTURE_PATH
	_assert("Reassigning the same source does not emit twice", _loaded_paths.size() == signal_count)

func _on_asset_loaded(path: String) -> void:
	_loaded_paths.append(path)

func _finish() -> void:
	print("FoveaSplat3D delegate contract: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)
