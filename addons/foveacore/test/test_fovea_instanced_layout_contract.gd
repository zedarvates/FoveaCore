extends SceneTree

## Non-GPU contract guard for the instanced 24-byte runtime record.
## This suite deliberately has no REQUIRES_GPU marker so the CI `nogpu` group
## catches shader/layout drift even when a RenderingDevice is unavailable.

const FoveaInstancedSplatLayout := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_splat_layout.gd")
const FoveaInstancedCuller := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_culler.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\nFovea Instanced Layout Contract Tests")
	_test_layout_constants()
	_test_shader_contract()
	print("Instanced layout contract: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _test_layout_constants() -> void:
	_assert("Canonical record remains 16 bytes", FoveaInstancedSplatLayout.CANONICAL_SPLAT_BYTE_SIZE == 16)
	_assert("Runtime record is 24 bytes", FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE == 24)
	_assert("local_idx follows canonical record", FoveaInstancedSplatLayout.LOCAL_IDX_OFFSET == 16)
	_assert("instance_id follows local_idx", FoveaInstancedSplatLayout.INSTANCE_ID_OFFSET == 20)
	_assert("Sparse delta sentinel matches DeltaEntry", FoveaInstancedCuller.DELTA_ENTRY_BYTE_SIZE == 16)
	_assert("Instanced push constant is std430-aligned", FoveaInstancedCuller.PUSH_CONSTANT_BYTE_SIZE == 64)

func _test_shader_contract() -> void:
	var culler_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/gpu_culling_instanced.glsl")
	var publish_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/shaders/publish_splats.glsl")
	var culler_script_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/scripts/advanced/fovea_instanced_culler.gd")
	var renderer_source: String = FileAccess.get_file_as_string(
		"res://addons/foveacore/scripts/advanced/fovea_instanced_splat_renderer.gd")
	_assert("Instanced culler shader is readable", not culler_source.is_empty())
	_assert("Publish shader is readable", not publish_source.is_empty())
	_assert("Instanced culler script is readable", not culler_script_source.is_empty())
	_assert("Instanced renderer script is readable", not renderer_source.is_empty())
	if culler_source.is_empty() or publish_source.is_empty() or culler_script_source.is_empty() or renderer_source.is_empty():
		return

	_assert("Culler preserves canonical data3", culler_source.contains("out_splat.data3 = splat.data3;"))
	_assert("Culler writes separate instance metadata", culler_source.contains("out_splat.instance_id = actual_instance_id;"))
	_assert("Culler output contains local_idx", culler_source.contains("uint local_idx;"))
	_assert("Culler output contains instance_id", culler_source.contains("uint instance_id;"))
	_assert("Publisher consumes extended output layout", publish_source.contains("struct OutputSplat"))
	_assert("Publisher emits only canonical words", publish_source.contains("uvec4(s.data0, s.data1, s.data2, s.data3)"))
	_assert("Shader uses deterministic count-first push ABI", culler_source.contains("uint asset_splat_count;\n    uint active_instances;"))
	_assert("Missing normals bypass backface rejection", culler_source.contains("if (has_encoded_normal && NdotV > params.camera_position.w) return;"))
	_assert("Unproven screen-space culling is fail-closed", culler_script_source.contains("push_bytes.encode_u32(12, 0)"))
	_assert("Shader gates screen-space rejection", culler_source.contains("if (params.enable_screen_space_culling == 1u)"))
	_assert("Disabled screen-space path preserves canonical records", culler_source.contains("passthrough_splat.data3 = splat.data3;"))
	_assert("Camera data uses a uniform buffer", culler_script_source.contains("UNIFORM_TYPE_UNIFORM_BUFFER"))
	_assert("Empty deltas allocate a sentinel", culler_script_source.contains("deltas_bytes.resize(DELTA_ENTRY_BYTE_SIZE)"))
	_assert("Local culler uses a local depth texture", culler_script_source.contains("var dummy_tex: RID = _create_dummy_depth_texture()"))
	_assert("Fallback reads the canonical splat count", renderer_source.contains("var splat_count: int = all_bytes.decode_u32(12)"))
	_assert("Fallback excludes trailing metadata", renderer_source.contains("all_bytes.slice(splats_start, splats_end)"))

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)
