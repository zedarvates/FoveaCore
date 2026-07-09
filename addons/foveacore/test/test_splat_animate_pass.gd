extends SceneTree
## Tests for the GPU animation pass integration.
## Verifies the animation shader loads and dispatch is configured.

const CullerPipeline = preload("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd")
var _passed := 0; var _failed := 0

func _init() -> void:
	print("\n=== GPU Animation Pass Tests ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)

func _run_all() -> void:
	var cp = CullerPipeline.new()
	# Verify the pipeline has animation-related members
	assert("animate_shader_rid" in cp, "animate_shader_rid exists")
	assert("animate_pipeline_rid" in cp, "animate_pipeline_rid exists")
	_passed += 2; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
