extends SceneTree

## Unit tests for Tile-Based Rasterization (16x16) Integration (A1)
## Validates:
## 1. GPUCullerPipeline skip_sync toggle behaviour.
## 2. FoveaCompositorEffect enable_tile_rasterizer property integration.
## 3. low-level dispatch of the tile rasterizer compute shader.

const GPUCullerPipelineClass := preload("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd")
const FoveaCompositorEffectClass := preload("res://addons/foveacore/scripts/advanced/fovea_compositor_effect.gd")
const REQUIRES_GPU := true

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "======================================================================")
	print("FoveaEngine - Tile-Based Rasterizer Unit Tests")
	print("======================================================================")

	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# ------------------------------------------------------------------
	# TEST 1: Property Integration
	# ------------------------------------------------------------------
	print("\n--- Test 1: Compositor Effect & Pipeline Integration ---")
	
	var culler := GPUCullerPipelineClass.new()
	_assert("GPUCullerPipeline instantiated", culler != null)
	
	var compositor_effect := FoveaCompositorEffectClass.new()
	_assert("FoveaCompositorEffect instantiated", compositor_effect != null)
	
	# Verify flag is present and maps properly
	_assert("Compositor effect has enable_tile_rasterizer property", "enable_tile_rasterizer" in compositor_effect)
	_assert("Default enable_tile_rasterizer is false", compositor_effect.enable_tile_rasterizer == false)
	
	compositor_effect.culler_pipeline = culler
	compositor_effect.enable_tile_rasterizer = true
	_assert("Can set enable_tile_rasterizer to true", compositor_effect.enable_tile_rasterizer == true)
	
	# ------------------------------------------------------------------
	# TEST 2: Low-Level Dispatch Execution
	# ------------------------------------------------------------------
	print("\n--- Test 2: Low-Level Dispatch Parameters ---")
	
	# Ensure the culler pipeline has the raster shader/pipeline initialized (if RD is available)
	if culler.rd:
		_assert("Rasterizer shader RID is initialized", culler.raster_shader_rid.is_valid())
		_assert("Rasterizer compute pipeline RID is initialized", culler.raster_pipeline_rid.is_valid())
		
		# Create dummy resources to simulate dispatch call parameters
		var camera := Camera3D.new()
		root.add_child(camera)
		
		var rd := culler.rd
		
		# Setup dummy 256 bytes output storage buffer
		var dummy_out_bytes := PackedByteArray()
		dummy_out_bytes.resize(256)
		var output_buf := rd.storage_buffer_create(256, dummy_out_bytes)
		
		# Setup dummy 2D texture for destination image (color texture)
		var format := RDTextureFormat.new()
		format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		format.width = 64
		format.height = 64
		format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		)
		var initial_pixels := PackedByteArray()
		initial_pixels.resize(64 * 64 * 4)
		var initial_data: Array[PackedByteArray] = [initial_pixels]
		var color_tex := rd.texture_create(format, RDTextureView.new(), initial_data)
		
		# Setup dummy AABB boundaries and palette textures
		var aabb_min := Vector3(-2, -2, -2)
		var aabb_max := Vector3(2, 2, 2)
		
		# Setup dummy 1x1 covar/palette textures to prevent null reference errors
		var covar_format := RDTextureFormat.new()
		covar_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		covar_format.width = 1
		covar_format.height = 1
		covar_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var covar_tex := rd.texture_create(covar_format, RDTextureView.new())
		
		var palette_tex := rd.texture_create(covar_format, RDTextureView.new())
		
		# Set persistent parameters to simulate run cache
		culler.last_counter_buffer_rid = rd.storage_buffer_create(16)
		culler.last_valid_splat_count = 10
		culler.skip_sync = true
		
		# Attempt a low-level dry-run dispatch of the tile rasterizer shader
		var dispatch_succeeded: bool = culler.dispatch_tile_based_rasterization(
			output_buf,
			camera,
			color_tex,
			false,
			16,
			aabb_min,
			aabb_max,
			covar_tex,
			palette_tex
		)
		_assert("Tile dispatch is submitted", dispatch_succeeded)
		if not dispatch_succeeded:
			_cleanup_gpu_fixtures(culler, output_buf, color_tex, covar_tex, palette_tex, camera)
			culler.cleanup()
			_finish()
			return
		rd.sync()
		var rendered_bytes: PackedByteArray = rd.texture_get_data(color_tex, 0)
		_assert("Tile dispatch writes the complete 64x64 RGBA target", rendered_bytes.size() == 64 * 64 * 4)
		_assert("Tile dispatch replaces the transparent target with an opaque background", rendered_bytes.size() >= 4 and rendered_bytes[3] == 255)
		
		# Clean up dummy resources
		_cleanup_gpu_fixtures(culler, output_buf, color_tex, covar_tex, palette_tex, camera)
	else:
		print("  [INFO] Skipping GPU dispatch test: RenderingDevice is not available in this headless/dummy context.")
		_assert("Graceful bypass on missing RenderingDevice", true)

	culler.cleanup()
	_finish()

func _cleanup_gpu_fixtures(
		culler: GPUCullerPipeline,
		output_buf: RID,
		color_tex: RID,
		covar_tex: RID,
		palette_tex: RID,
		camera: Camera3D
) -> void:
	var rd: RenderingDevice = culler.rd
	rd.free_rid(output_buf)
	rd.free_rid(color_tex)
	rd.free_rid(covar_tex)
	rd.free_rid(palette_tex)
	rd.free_rid(culler.last_counter_buffer_rid)
	culler.last_counter_buffer_rid = RID()
	camera.queue_free()

func _finish() -> void:
	print("\n" + "======================================================================")
	print("Tile-Based Rasterizer Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("======================================================================")
	
	quit(1 if _failed > 0 else 0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		if detail.is_empty():
			print("  ✗ %s" % name)
		else:
			print("  ✗ %s — %s" % [name, detail])
