extends SceneTree

## GPU shader compilation gate (item 313).
## Verifies that every imported GLSL resource exposes SPIR-V without a compiler error.
const REQUIRES_GPU := true
const SHADER_DIR := "res://addons/foveacore/shaders/"
const SHADER_STAGES := [
	RenderingDevice.SHADER_STAGE_VERTEX,
	RenderingDevice.SHADER_STAGE_FRAGMENT,
	RenderingDevice.SHADER_STAGE_TESSELATION_CONTROL,
	RenderingDevice.SHADER_STAGE_TESSELATION_EVALUATION,
	RenderingDevice.SHADER_STAGE_COMPUTE,
]

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n=== GPU Shader Compilation Tests (item 313) ===")
	_run_all()
	await create_timer(0.1).timeout
	quit(1 if _failed > 0 else 0)

func _run_all() -> void:
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	_assert("Local RenderingDevice is available", rd != null)
	if rd == null:
		return

	var dir := DirAccess.open(SHADER_DIR)
	_assert("Shader directory opens", dir != null)
	if dir == null:
		rd.free()
		return

	var shader_paths: PackedStringArray = []
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if filename.ends_with(".glsl") and not filename.ends_with(".glsl.import"):
			shader_paths.append(SHADER_DIR.path_join(filename))
		filename = dir.get_next()
	dir.list_dir_end()
	shader_paths.sort()
	_assert("At least one GLSL shader is present", not shader_paths.is_empty())

	for path: String in shader_paths:
		var shader_file := load(path) as RDShaderFile
		_assert("%s imports as RDShaderFile" % path.get_file(), shader_file != null)
		if shader_file == null:
			continue
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		_assert("%s exposes SPIR-V" % path.get_file(), spirv != null)
		if spirv == null:
			continue
		for stage: int in SHADER_STAGES:
			_assert("%s stage %d has no compile error" % [path.get_file(), stage], spirv.get_stage_compile_error(stage).is_empty())

	rd.free()
	print("Shader compilation: %d passed, %d failed" % [_passed, _failed])

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		push_error("  ✗ %s" % name)
