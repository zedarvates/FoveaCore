extends SceneTree

## Non-GPU contract guard for the instanced 24-byte runtime record.
## This suite deliberately has no REQUIRES_GPU marker so the CI `nogpu` group
## catches shader/layout drift even when a RenderingDevice is unavailable.

const FoveaInstancedSplatLayout := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_splat_layout.gd")
const FoveaInstancedCuller := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_culler.gd")
const FoveaInstancedSplatRenderer := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_splat_renderer.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\nFovea Instanced Layout Contract Tests")
	_test_layout_constants()
	_test_cpu_passthrough_records()
	_test_canonical_asset_fallback()
	_test_shader_contract()
	await _test_headless_cpu_runtime()
	print("Instanced layout contract: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _test_layout_constants() -> void:
	_assert("Canonical record remains 16 bytes", FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE == 16)
	_assert("Runtime record is 24 bytes", FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE == 24)
	_assert("local_idx follows canonical record", FoveaInstancedSplatLayout.LOCAL_IDX_OFFSET == 16)
	_assert("instance_id follows local_idx", FoveaInstancedSplatLayout.INSTANCE_ID_OFFSET == 20)
	_assert("Sparse delta sentinel matches DeltaEntry", FoveaInstancedCuller.DELTA_ENTRY_BYTE_SIZE == 16)
	_assert("Instanced push constant is std430-aligned", FoveaInstancedCuller.PUSH_CONSTANT_BYTE_SIZE == 64)

func _test_cpu_passthrough_records() -> void:
	var canonical: PackedByteArray = PackedByteArray()
	canonical.resize(2 * FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE)
	canonical.encode_u32(12, 0x04AD00FF)
	canonical.encode_u32(28, 0x02B4007F)
	var records: PackedByteArray = FoveaInstancedSplatRenderer._build_cpu_passthrough_records(canonical, 2)
	_assert("CPU passthrough emits two splats per instance", records.size() == 4 * FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE)
	_assert("CPU passthrough preserves first canonical data3", records.decode_u32(12) == 0x04AD00FF)
	_assert("CPU passthrough preserves second canonical data3", records.decode_u32(24 + 12) == 0x02B4007F)
	_assert("CPU passthrough writes local index", records.decode_u32(24 + FoveaInstancedSplatLayout.LOCAL_IDX_OFFSET) == 1)
	_assert("CPU passthrough writes compact instance id", records.decode_u32(2 * 24 + FoveaInstancedSplatLayout.INSTANCE_ID_OFFSET) == 1)
	_assert("CPU passthrough rejects unaligned input", FoveaInstancedSplatRenderer._build_cpu_passthrough_records(PackedByteArray([1]), 1).is_empty())

func _test_canonical_asset_fallback() -> void:
	var renderer := FoveaInstancedSplatRenderer.new()
	renderer.asset_path = "res://test/demo_bonsai.fovea"
	var asset: FoveaAsset = renderer._load_canonical_fovea_asset()
	_assert("Canonical bonsai fallback loads", asset != null)
	if asset == null:
		renderer.free()
		return
	_assert("Canonical fallback keeps 12,473 splats", asset.splat_count == 12473)
	_assert("Canonical fallback keeps exact splat bytes", asset.splats_raw_bytes.size() == 12473 * FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE)
	_assert("Canonical fallback keeps 256 colors", asset.color_palette != null and asset.color_palette.colors.size() == 256)
	_assert("Canonical fallback resolves brown palette index", asset.color_palette != null and asset.color_palette.get_color(4).is_equal_approx(Color(0.45, 0.32, 0.18)))
	_assert("Canonical fallback resolves green palette index", asset.color_palette != null and asset.color_palette.get_color(38).is_equal_approx(Color(0.15, 0.85, 0.55)))
	_assert("Canonical fallback keeps 1,024 covariances", asset.covariance_codebook.size() == 1024 * 32)
	_assert("Canonical fallback uses real AABB", asset.aabb_min.is_equal_approx(Vector3(-0.84776264, -0.50746137, -0.54227507)) and asset.aabb_max.is_equal_approx(Vector3(1.0542464, 2.0878868, 1.3464916)))
	renderer.free()

func _test_shader_contract() -> void:
	var culler_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/gpu_culling_instanced.glsl")
	var publish_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/publish_splats.glsl")
	var culler_script_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/scripts/advanced/fovea_instanced_culler.gd")
	var renderer_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/scripts/advanced/fovea_instanced_splat_renderer.gd")
	var triangle_shader_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/splat_render_triangle.gdshader")
	var palette_shader_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/splat_render_triangle_palette.gdshader")
	var math_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/splat_math.gdshaderinc")
	var gpu_pipeline_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd")
	_assert("Instanced culler shader is readable", not culler_source.is_empty())
	_assert("Publish shader is readable", not publish_source.is_empty())
	_assert("Instanced culler script is readable", not culler_script_source.is_empty())
	_assert("Instanced renderer script is readable", not renderer_source.is_empty())
	_assert("Native triangle shaders are readable", not triangle_shader_source.is_empty() and not palette_shader_source.is_empty())
	_assert("Splat math include is readable", not math_source.is_empty())
	_assert("GPU pipeline script is readable", not gpu_pipeline_source.is_empty())
	if culler_source.is_empty() or publish_source.is_empty() or culler_script_source.is_empty() or renderer_source.is_empty() or triangle_shader_source.is_empty() or palette_shader_source.is_empty() or math_source.is_empty() or gpu_pipeline_source.is_empty():
		return

	_assert("Culler preserves canonical data3", culler_source.contains("out_splat.data3 = splat.data3;"))
	_assert("Culler writes separate instance metadata", culler_source.contains("out_splat.instance_id = actual_instance_id;"))
	_assert("Culler output contains local_idx", culler_source.contains("uint local_idx;"))
	_assert("Culler output contains instance_id", culler_source.contains("uint instance_id;"))
	_assert("Publisher consumes extended output layout", publish_source.contains("struct OutputSplat"))
	_assert("Publisher emits only canonical words", publish_source.contains("uvec4(s.data0, s.data1, s.data2, s.data3)"))
	_assert("Shader exposes explicit std430 padding", culler_source.contains("vec2 pad0;"))
	_assert("Camera data uses a uniform buffer", culler_script_source.contains("UNIFORM_TYPE_UNIFORM_BUFFER"))
	_assert("Empty deltas allocate a sentinel", culler_script_source.contains("deltas_bytes.resize(DELTA_ENTRY_BYTE_SIZE)"))
	_assert("Local culler uses a local depth texture", culler_script_source.contains("var dummy_tex: RID = _create_dummy_depth_texture()"))
	_assert("Fallback reads the canonical splat count", renderer_source.contains("var splat_count: int = all_bytes.decode_u32(12)"))
	_assert("Fallback excludes trailing metadata", renderer_source.contains("all_bytes.slice(splats_start, splats_end)"))
	_assert("Default runtime keeps compute culling experimental", renderer_source.contains("@export var enable_experimental_gpu_culling: bool = false"))
	_assert("CPU fallback does not require a RenderingDevice", not renderer_source.contains("if not camera or not instanced_culler or instanced_culler.rd == null:"))
	_assert("Compute opt-in fails closed without a RenderingDevice", renderer_source.contains("if instanced_culler.rd == null:"))
	_assert("Missing encoded normals bypass backface rejection", culler_source.contains("if (has_encoded_normal && NdotV > params.backface_threshold) return;"))
	_assert("Native covariance uses canonical 32-byte stride", renderer_source.contains("FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE"))
	_assert("Native shaders support linear covariance scale", triangle_shader_source.contains("covar_scale_is_linear") and palette_shader_source.contains("covar_scale_is_linear"))
	_assert("Instanced renderer activates linear covariance scale", renderer_source.contains("mat.set_shader_parameter(\"covar_scale_is_linear\", true)"))
	_assert("Linear covariance helper avoids a second exp", math_source.contains("mat3 compute_cov3d_linear") and math_source.contains("S[0][0] = max(scale.x"))
	_assert("Palette shader reads the vertical texture", palette_shader_source.contains("vec2 palette_uv = vec2(0.5, palette_v);"))
	_assert("Palette shader uses fragment coordinates for dithering", palette_shader_source.contains("apply_floyd_steinberg_dither(FRAGCOORD.xy"))
	_assert("Palette textures request nearest filtering in shader", triangle_shader_source.contains("filter_nearest, repeat_disable") and palette_shader_source.contains("filter_nearest, repeat_disable"))
	_assert("Godot 4.7 palette upload avoids removed filter_clip", not renderer_source.contains("tex.filter_clip"))
	_assert("GPU cache cleanup owns dynamic output", gpu_pipeline_source.contains("\"dynamic_output\","))
	_assert("GPU cache cleanup releases uniform dependencies first", gpu_pipeline_source.find("for key: String in uniform_keys:") < gpu_pipeline_source.find("for key: String in resource_keys:"))
	_assert("Local RenderingDevice cleanup submits before sync", gpu_pipeline_source.contains("rd.submit()\n        rd.sync()"))

func _test_headless_cpu_runtime() -> void:
	var camera := Camera3D.new()
	camera.look_at_from_position(
		Vector3(0.0, 1.0, 5.0),
		Vector3(0.0, 0.8, 0.0),
		Vector3.UP
	)
	root.add_child(camera)
	camera.current = true

	var renderer := FoveaInstancedSplatRenderer.new()
	renderer.asset_path = "res://test/demo_bonsai.fovea"
	renderer.instance_transforms = [Transform3D.IDENTITY]
	renderer.enable_cleaning = false
	root.add_child(renderer)
	await process_frame
	_assert("Headless runtime uses the CPU fallback", renderer.multimesh != null and renderer.multimesh.instance_count == 12473)
	renderer.queue_free()
	camera.queue_free()
	await process_frame

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)
