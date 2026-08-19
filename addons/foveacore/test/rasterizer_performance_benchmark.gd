extends SceneTree

# GPU benchmark script to compare a modeled MultiMesh baseline with tile rasterization (Task 242).
# The MultiMesh figures are estimates; only the tile dispatch duration is measured.
const REQUIRES_GPU := true
const EXPECTED_CASES := 9
const BYTES_PER_CANONICAL_SPLAT := 16

const GPUCullerPipelineClass := preload("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd")
const FoveaCompositorEffectClass := preload("res://addons/foveacore/scripts/advanced/fovea_compositor_effect.gd")

var _results: Array[Dictionary] = []

func _init() -> void:
	print("\n======================================================================")
	print("FoveaEngine - Rasterizer Performance Benchmark (Task 242)")
	print("======================================================================")
	await create_timer(0.2).timeout
	_run_benchmark()

func _run_benchmark() -> void:
	var resolutions = [
		Vector2i(512, 512),
		Vector2i(1024, 1024),
		Vector2i(2048, 2048)
	]
	
	var splat_densities = [1000, 10000, 50000]

	for res in resolutions:
		for density in splat_densities:
			_benchmark_combination(res, density)

	if _results.size() != EXPECTED_CASES:
		push_error("Rasterizer benchmark aborted: %d/%d GPU cases completed." % [_results.size(), EXPECTED_CASES])
		quit(1)
		return
	_generate_report()
	quit(0)

func _benchmark_combination(res: Vector2i, density: int) -> void:
	print("\nBenchmarking Resolution: %dx%d | Splat Count: %d" % [res.x, res.y, density])
	
	var culler := GPUCullerPipelineClass.new()
	if not culler.rd:
		push_error("Rasterizer benchmark requires a local RenderingDevice; no result is recorded.")
		culler.cleanup()
		return
		
	var rd := culler.rd
	
	# Setup dummy textures and buffers
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = res.x
	format.height = res.y
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var color_tex := rd.texture_create(format, RDTextureView.new())
	
	# The rasterizer shader consumes canonical PackedSplat records (16 bytes each).
	var output_bytes := density * BYTES_PER_CANONICAL_SPLAT
	if output_bytes <= 0:
		push_error("Rasterizer benchmark invalid output buffer size: %d" % output_bytes)
		_cleanup_benchmark_resources(rd, RID(), color_tex, RID(), RID(), culler, camera)
		return

	var dummy_out_bytes := PackedByteArray()
	dummy_out_bytes.resize(output_bytes)
	var output_buf := rd.storage_buffer_create(output_bytes, dummy_out_bytes)
	if not output_buf.is_valid():
		push_error("Rasterizer benchmark failed to create output storage buffer (%d bytes)." % output_bytes)
		_cleanup_benchmark_resources(rd, RID(), color_tex, covar_tex, palette_tex, culler, camera)
		return
	
	var covar_format := RDTextureFormat.new()
	covar_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	covar_format.width = 1
	covar_format.height = 1
	covar_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var covar_tex := rd.texture_create(covar_format, RDTextureView.new())
	var palette_tex := rd.texture_create(covar_format, RDTextureView.new())
	
	culler.last_counter_buffer_rid = rd.storage_buffer_create(16)
	culler.last_valid_splat_count = density
	
	var camera := Camera3D.new()
	root.add_child(camera)
	
	# 1. Benchmark MultiMesh / Vertex Shader simulated dispatch or draw (dummy estimation)
	var mm_base_fps := 60.0
	var overdraw_factor := float(density) / 5000.0
	var mm_frame_time_ms := 0.2 + (density * 0.0001) + (res.x * res.y * 0.000001 * overdraw_factor)
	var mm_fps := 1000.0 / mm_frame_time_ms
	
	# 2. Benchmark Tile-Based Rasterizer (Real compute dispatch measurement)
	var start_time := Time.get_ticks_usec()
	var iterations := 10
	
	for i in range(iterations):
		culler.dispatch_tile_based_rasterization(
			output_buf,
			camera,
			color_tex,
			false,
			16,
			Vector3(-2, -2, -2),
			Vector3(2, 2, 2),
			covar_tex,
			palette_tex
		)
		
	# Wait for GPU execution to complete
	rd.submit()
	rd.sync()
	
	var end_time := Time.get_ticks_usec()
	var avg_dispatch_time_ms := float(end_time - start_time) / (1000.0 * iterations)
	
	var tile_fps := 1000.0 / avg_dispatch_time_ms
	
	print("  -> MultiMesh Est. Frame Time: %.2f ms (%.1f FPS)" % [mm_frame_time_ms, mm_fps])
	print("  -> Tile-Based Avg GPU Dispatch: %.2f ms (%.1f FPS)" % [avg_dispatch_time_ms, tile_fps])
	
	_results.append({
		"resolution": "%dx%d" % [res.x, res.y],
		"density": density,
		"mm_time_ms": mm_frame_time_ms,
		"mm_fps": mm_fps,
		"tile_time_ms": avg_dispatch_time_ms,
		"tile_fps": tile_fps,
		"gain": (tile_fps / mm_fps - 1.0) * 100.0
	})
	
	# Clean up
	_cleanup_benchmark_resources(rd, output_buf, color_tex, covar_tex, palette_tex, culler, camera)

func _cleanup_benchmark_resources(
	rd: RenderingDevice,
	output_buf: RID,
	color_tex: RID,
	covar_tex: RID,
	palette_tex: RID,
	culler: GPUCullerPipelineClass,
	camera: Camera3D
) -> void:
	if not rd:
		return
	if output_buf.is_valid():
		rd.free_rid(output_buf)
	if color_tex.is_valid():
		rd.free_rid(color_tex)
	if covar_tex.is_valid():
		rd.free_rid(covar_tex)
	if palette_tex.is_valid():
		rd.free_rid(palette_tex)
	if culler.last_counter_buffer_rid.is_valid():
		rd.free_rid(culler.last_counter_buffer_rid)
	if camera:
		camera.queue_free()
	culler.cleanup()

func _generate_report() -> void:
	var report_path := "user://benchmark_rasterizer_comparison.md"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if not file:
		print("  [ERROR] Cannot write report to ", report_path)
		return
		
	file.store_line("# Rasterizer GPU Dispatch Report (Task 242)")
	file.store_line("\nTile dispatch time is measured with a local RenderingDevice. MultiMesh time is a model-derived estimate and is not a measured comparison.")
	file.store_line("\n## Benchmark Results Table\n")
	file.store_line("| Resolution | Splat Count | MultiMesh Time (ms) | MultiMesh FPS | Tile-Based GPU Time (ms) | Tile-Based FPS | Gain (%) |")
	file.store_line("|---|---|---|---|---|---|---|")
	
	for r in _results:
		file.store_line("| %s | %d | %.2f | %.1f | %.2f | %.1f | %+.1f%% |" % [
			r.resolution, r.density, r.mm_time_ms, r.mm_fps, r.tile_time_ms, r.tile_fps, r.gain
		])
		
	file.store_line("\n## Scope")
	file.store_line("- Tile-Based GPU Time is a synchronized dispatch measurement, not a full rendered-frame measurement.")
	file.store_line("- MultiMesh Time is an estimate and must not be used to claim a measured speedup.")
	
	file.close()
	print("\nBenchmark completed. Report written to: ", report_path)
