extends SceneTree

## Unit test for GPU-Driven Rendering & Indirect Draw pipeline.
## Validates that FoveaCoreSplatRenderer with enable_gpu_driven skips CPU readbacks,
## binds Texture2DRD uniforms to the material, and compiles compute shaders.

const FoveaAssetWriterScript := preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const FoveaStyleScript := preload("res://addons/foveacore/scripts/fovea_style.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n==============================================================")
	print("GPU-Driven Renderer Pipeline Unit Tests")
	print("==============================================================")

	await create_timer(0.3).timeout
	_run_tests()

func _assert(desc: String, cond: bool, err_msg := "") -> void:
	if cond:
		_passed += 1
		print("[PASS] ", desc)
	else:
		_failed += 1
		print("[FAIL] ", desc, ". Details: ", err_msg)

func _run_tests() -> void:
	# 1. Create a tiny test .fovea asset
	var splats: Array[GaussianSplat] = []
	for i in range(15):
		var s := GaussianSplatScript.new(Vector3(float(i) * 0.2, 0.0, -float(i) * 0.2))
		s.scale = Vector3(1.0, 1.0, 1.0)
		s.rotation = Quaternion.IDENTITY
		s.color = Color(1.0, 0.0, 0.0, 1.0)
		s.opacity = 1.0
		s.normal = Vector3(0.0, 1.0, 0.0)
		s.layer_type = 0
		s.dither_seed = i
		splats.append(s as GaussianSplat)
		
	var style := FoveaStyleScript.new()
	style.mode = "procedural"
	
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)])
	var indices := PackedInt32Array([0, 1, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var test_path := "user://test_gpu_driven.fovea"
	var write_success := FoveaAssetWriterScript.write_fovea_asset(test_path, splats, mesh, style, {})
	_assert("Test asset generated at " + test_path, write_success)
	
	# 2. Setup rendering viewport and camera
	var viewport := SubViewport.new()
	root.add_child(viewport)
	
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.global_position = Vector3(0.0, 2.0, 5.0)
	camera.look_at(Vector3.ZERO)
	
	# 3. Create and configure FoveaCoreSplatRenderer
	var renderer := FoveaCoreSplatRenderer.new()
	renderer.enable_gpu_driven = true
	renderer.asset_path = test_path
	viewport.add_child(renderer)
	
	# Force process to initialize nodes and run pipeline
	renderer._process(0.016)
	
	# 4. Perform pipeline verification
	_assert("Culler pipeline created", renderer.culler_pipeline != null)
	if renderer.culler_pipeline:
		_assert("skip_sync parameter is true on culler", renderer.culler_pipeline.skip_sync)
		
		# Validate that shader compiled
		if renderer.culler_pipeline.rd:
			_assert("publish_shader_rid is valid", renderer.culler_pipeline.publish_shader_rid.is_valid())
			_assert("publish_pipeline_rid is valid", renderer.culler_pipeline.publish_pipeline_rid.is_valid())
			
			# Validate that textures were created and cached
			var cache: Dictionary = renderer.culler_pipeline._gpu_buffers.get(test_path, {})
			_assert("GPU culler cache exists for asset", not cache.is_empty())
			if not cache.is_empty():
				_assert("output_texture exists in cache", cache.get("output_texture", RID()).is_valid())
				_assert("counter_texture exists in cache", cache.get("counter_texture", RID()).is_valid())
				_assert("publish_uniform_set exists in cache", cache.get("publish_uniform_set", RID()).is_valid())
				
				# Validate Texture2DRD uniforms on material
				var mat := renderer.material_override as ShaderMaterial
				_assert("Material exists", mat != null)
				if mat:
					_assert("enable_gpu_driven is true on material", mat.get_shader_parameter("enable_gpu_driven") == true)
					
					var out_tex = mat.get_shader_parameter("output_texture")
					var cnt_tex = mat.get_shader_parameter("counter_texture")
					
					_assert("output_texture uniform is Texture2DRD", out_tex is Texture2DRD)
					if out_tex is Texture2DRD:
						_assert("output_texture wraps valid RID", out_tex.texture_rd_rid == cache["output_texture"])
						
					_assert("counter_texture uniform is Texture2DRD", cnt_tex is Texture2DRD)
					if cnt_tex is Texture2DRD:
						_assert("counter_texture wraps valid RID", cnt_tex.texture_rd_rid == cache["counter_texture"])
						
					_assert("MultiMesh instance count matches total_splats", renderer.multimesh.instance_count == 15)
	
	# Cleanup
	renderer.queue_free()
	camera.queue_free()
	viewport.queue_free()
	
	if DirAccess.dir_exists_absolute("user://"):
		var dir := DirAccess.open("user://")
		if dir.file_exists("test_gpu_driven.fovea"):
			dir.remove("test_gpu_driven.fovea")
			
	print("\n==============================================================")
	print("GPU-Driven Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("==============================================================")
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)
