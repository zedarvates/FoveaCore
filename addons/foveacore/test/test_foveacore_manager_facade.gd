extends SceneTree

## Non-GPU runtime contract for the FoveaCoreManager autoload facade.
## This validates orchestration and public controls only; GPU and XR execution
## remain separate hardware gates.

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\nFoveaCoreManager Facade Contract Tests")
	await process_frame

	var manager: FoveaCoreManagerScript = root.get_node_or_null("FoveaCoreManager") as FoveaCoreManagerScript
	_assert("Manager autoload exists", manager != null)
	if manager == null:
		_finish()
		return

	_test_orchestration(manager)
	_test_public_controls(manager)
	_test_fail_closed_refresh(manager)
	_finish()

func _test_orchestration(manager: FoveaCoreManagerScript) -> void:
	_assert("Manager completed initialization", manager.renderer_initialized)
	_assert("VR subsystem is owned", manager._vr != null and manager._vr.get_parent() == manager)
	_assert("Foveated subsystem is owned", manager._foveated != null and manager._foveated.get_parent() == manager)
	_assert("Animation subsystem is owned", manager._animation != null and manager._animation.get_parent() == manager)
	_assert("Splat subsystem is owned", manager._splat_pipeline != null and manager._splat_pipeline.get_parent() == manager)
	_assert("Foveated controller is initialized", manager._foveated.get_controller() != null)
	_assert("Layered foveated controller is initialized", manager._foveated.get_layered_controller() != null)
	_assert("Splat pipeline receives temporal reprojection", manager._splat_pipeline.temporal_reprojector == manager._temporal_reprojector)
	_assert("Splat pipeline receives occlusion culling", manager._splat_pipeline.occlusion_culler == manager._occlusion_culler)
	_assert("Splat pipeline receives depth sorting", manager._splat_pipeline.splat_sorter == manager._splat_sorter)
	_assert("Splat pipeline receives rendering", manager._splat_pipeline.splat_renderer == manager._splat_renderer)
	_assert("Splat pipeline receives animation", manager._splat_pipeline.animation_subsystem == manager._animation)
	_assert("Splat limit propagates into the pipeline", manager._splat_pipeline.max_splats == manager.max_splats_per_frame)
	_assert("Foveated radius propagates into the subsystem", is_equal_approx(manager._foveated.foveal_radius, manager.foveal_radius))
	_assert(
		"Desktop fallback keeps renderer foveation disabled",
		manager._vr.is_xr_active or not manager._splat_renderer.enable_foveated_rendering
	)

func _test_public_controls(manager: FoveaCoreManagerScript) -> void:
	var original_density: float = manager.global_splat_density
	var original_animation: bool = manager.animation_enabled
	var original_foveated: bool = manager.foveated_enabled
	var original_style: FoveaStyle = manager.active_style
	var original_hybrid: bool = manager.hybrid_mode_enabled

	manager.set_splat_density(-2.0)
	_assert("Density clamps to the lower bound", is_equal_approx(manager.global_splat_density, 0.1))
	_assert("Lower density propagates to the pipeline", is_equal_approx(manager._splat_pipeline.global_splat_density, 0.1))
	manager.set_splat_density(9.0)
	_assert("Density clamps to the upper bound", is_equal_approx(manager.global_splat_density, 5.0))
	_assert("Upper density propagates to the pipeline", is_equal_approx(manager._splat_pipeline.global_splat_density, 5.0))

	manager.toggle_animation(false)
	_assert("Animation disable reaches the subsystem", not manager.animation_enabled and not manager._animation.enabled)
	manager.toggle_animation(true)
	_assert("Animation enable reaches the subsystem", manager.animation_enabled and manager._animation.enabled)
	_assert("Animation accessor returns the owned subsystem", manager.get_animation_subsystem() == manager._animation)

	manager.toggle_foveated(true)
	_assert("Foveated enable reaches the renderer", manager.foveated_enabled and manager._splat_renderer.enable_foveated_rendering)
	manager.toggle_foveated(false)
	_assert("Foveated disable reaches the renderer", not manager.foveated_enabled and not manager._splat_renderer.enable_foveated_rendering)

	var style: FoveaStyle = FoveaStyle.new()
	style.mode = "neural"
	manager.set_style(style)
	_assert("Style setter retains the selected resource", manager.active_style == style)

	manager.toggle_hybrid_mode()
	_assert("Hybrid toggle updates facade state", manager.hybrid_mode_enabled != original_hybrid)
	_assert(
		"Hybrid toggle updates renderer mode",
		manager._hybrid_renderer.current_mode == HybridRenderer.RenderMode.HYBRID
			if manager.hybrid_mode_enabled
			else manager._hybrid_renderer.current_mode == HybridRenderer.RenderMode.SPLAT_ONLY
	)
	manager.toggle_hybrid_mode()
	_assert("Second hybrid toggle restores facade state", manager.hybrid_mode_enabled == original_hybrid)

	manager.set_splat_density(original_density)
	manager.toggle_animation(original_animation)
	manager.toggle_foveated(original_foveated)
	manager.active_style = original_style

func _test_fail_closed_refresh(manager: FoveaCoreManagerScript) -> void:
	var renderer_count: int = manager._instanced_renderers.size()
	var detached: FoveaSplattable = FoveaSplattable.new()
	detached.splat_file_path = "res://detached.fovea"
	manager.refresh_splattable_asset(detached)
	_assert("Detached refresh does not create a renderer", manager._instanced_renderers.size() == renderer_count)
	detached.free()

func _finish() -> void:
	print("FoveaCoreManager facade contract: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)
