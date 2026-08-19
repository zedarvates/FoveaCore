extends SceneTree
## Tests for the implemented GPU delta-animation pass integration.
## `splat_animate.glsl` is not yet initialized or dispatched by GPUCullerPipeline.
const REQUIRES_GPU := true

const CullerPipeline = preload("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd")
var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n=== GPU Delta Animation Pass Tests ===")
	_run_all()
	await create_timer(0.1).timeout
	quit(1 if _failed > 0 else 0)

func _run_all() -> void:
	var cp = CullerPipeline.new()
	_assert("Local RenderingDevice is available", cp.rd != null)
	if cp.rd != null:
		_assert("Delta animation shader RID is valid", cp.delta_shader_rid.is_valid())
		_assert("Delta animation compute pipeline is valid", cp.delta_pipeline_rid.is_valid())
	cp.cleanup()
	print("  %d/%d" % [_passed, _passed + _failed])

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		push_error("  ✗ %s" % name)
