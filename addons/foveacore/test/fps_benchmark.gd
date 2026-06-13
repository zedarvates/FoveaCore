extends SceneTree
## Reproducible FPS benchmark for the FoveaSplat3D render path (Phase 0, C6).
##
## Generates N splats, drops a FoveaSplat3D into a live scene, orbits a camera for
## a fixed duration while sampling real frame times, and writes a JSON report:
##   { splats, fps_avg, fps_1pct_low, frame_ms_avg, frame_ms_p99, meets_90fps }
##
## Must run WINDOWED (real rendering) — not --headless (dummy renderer = no GPU work):
##   godot --path . -s res://addons/foveacore/test/fps_benchmark.gd -- \
##       --splats=1000000 --duration=12 --out=user://benchmark_report.json
##
## Threshold for the README headline: 90 FPS @ 1,000,000 splats, 1080p desktop.
## The number is hardware-dependent, so the process never fails on it — it only
## reports meets_90fps. Use scripts/run_benchmark.ps1 for a turnkey run.

const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const FoveaSplat3DScript := preload("res://addons/foveacore/scripts/fovea_splat_3d.gd")

const TARGET_FPS := 90.0
# Warmup is counted in FRAMES, not wall-clock: the one-time PLY load + HLOD
# generation can take seconds and lands in a single frame — a wall-clock warmup
# would otherwise capture that load stall as a "render frame". Skip enough frames
# for the load to fully settle before sampling steady-state.
const WARMUP_FRAMES := 90
const MIN_SAMPLES := 120     # ensure a meaningful sample even on a slow path
const SAFETY_CAP_S := 60.0   # hard wall-clock cap so the loop can never hang

var _splats := 200000
var _duration := 10.0
var _out := "user://benchmark_report.json"

func _init() -> void:
	_parse_args()
	print("\n" + "=".repeat(70))
	print("FoveaEngine FPS Benchmark — %d splats, %.1fs (+%d warmup frames)" % [_splats, _duration, WARMUP_FRAMES])
	print("=".repeat(70))

	await create_timer(0.2).timeout

	# Generate a transient PLY of N splats and load it through the real user path.
	var ply_path := "user://_bench_%d.ply" % _splats
	_write_synthetic_ply(ply_path, _splats)

	var world := Node3D.new()
	get_root().add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)
	env.environment = e
	world.add_child(env)

	var cam := Camera3D.new()
	cam.current = true
	world.add_child(cam)

	var splat: Node3D = FoveaSplat3DScript.new()
	world.add_child(splat)
	splat.source_path = ply_path

	# Orbit radius from the generated extent (box is ~4x3x4).
	var radius := 4.0
	var center := Vector3.ZERO

	var frame_us: Array[float] = []
	var frame_idx := 0
	var collect_start := 0
	var last := Time.get_ticks_usec()
	var angle := 0.0

	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt_us := float(now - last)
		last = now
		frame_idx += 1

		# Orbit the camera.
		angle += 0.6 * (dt_us / 1_000_000.0)
		cam.global_position = center + Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		cam.look_at(center, Vector3.UP)

		if frame_idx <= WARMUP_FRAMES:
			if frame_idx == WARMUP_FRAMES:
				collect_start = now  # reset the clock once load/HLOD has settled
			continue

		frame_us.append(dt_us)
		var elapsed := float(now - collect_start) / 1_000_000.0
		# Stop once we have both enough wall-clock AND enough samples; never hang.
		if (elapsed >= _duration and frame_us.size() >= MIN_SAMPLES) or elapsed >= SAFETY_CAP_S:
			break

	_report(frame_us)
	world.queue_free()
	quit(0)


func _report(frame_us: Array[float]) -> void:
	if frame_us.is_empty():
		push_error("FPS Benchmark: no frames collected")
		quit(1)
		return

	frame_us.sort()
	var n := frame_us.size()
	var sum := 0.0
	for v in frame_us:
		sum += v
	var mean_us := sum / n
	# 99th percentile frame time → "1% low" FPS.
	var p99_us: float = frame_us[mini(n - 1, int(ceil(0.99 * n)) - 1)]

	var fps_avg := 1_000_000.0 / mean_us
	var fps_1pct_low := 1_000_000.0 / p99_us
	var meets := fps_avg >= TARGET_FPS

	var report := {
		"splats": _splats,
		"frames_sampled": n,
		"duration_s": _duration,
		"fps_avg": snappedf(fps_avg, 0.1),
		"fps_1pct_low": snappedf(fps_1pct_low, 0.1),
		"frame_ms_avg": snappedf(mean_us / 1000.0, 0.01),
		"frame_ms_p99": snappedf(p99_us / 1000.0, 0.01),
		"target_fps": TARGET_FPS,
		"meets_90fps": meets,
		"gpu": RenderingServer.get_video_adapter_name(),
	}

	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()

	print("\n" + "-".repeat(70))
	print("  splats         : %d" % _splats)
	print("  fps_avg        : %.1f" % report.fps_avg)
	print("  fps_1pct_low   : %.1f" % report.fps_1pct_low)
	print("  frame_ms_avg   : %.2f" % report.frame_ms_avg)
	print("  frame_ms_p99   : %.2f" % report.frame_ms_p99)
	print("  gpu            : %s" % report.gpu)
	print("  meets 90 FPS   : %s" % ("YES" if meets else "NO"))
	print("  report written : %s" % _out)
	print("-".repeat(70))


## Writes a binary little-endian 3DGS PLY with `count` seeded splats.
func _write_synthetic_ply(path: String, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	var f := FileAccess.open(path, FileAccess.WRITE)
	var header := "ply\nformat binary_little_endian 1.0\nelement vertex %d\n" % count
	for p in ["x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2",
			"opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]:
		header += "property float %s\n" % p
	header += "end_header\n"
	f.store_string(header)
	for _i in range(count):
		f.store_float(rng.randf_range(-2.0, 2.0))   # x
		f.store_float(rng.randf_range(-1.5, 1.5))   # y
		f.store_float(rng.randf_range(-2.0, 2.0))   # z
		f.store_float(0.0); f.store_float(1.0); f.store_float(0.0)  # normal
		f.store_float(rng.randf_range(-1.5, 1.5))   # f_dc_0
		f.store_float(rng.randf_range(-1.5, 1.5))   # f_dc_1
		f.store_float(rng.randf_range(-1.5, 1.5))   # f_dc_2
		f.store_float(rng.randf_range(-2.0, 4.0))   # opacity (logit)
		f.store_float(rng.randf_range(-5.0, -2.0))  # scale_0 (log)
		f.store_float(rng.randf_range(-5.0, -2.0))  # scale_1
		f.store_float(rng.randf_range(-5.0, -2.0))  # scale_2
		f.store_float(1.0); f.store_float(0.0); f.store_float(0.0); f.store_float(0.0)  # rot
	f.close()
	print("  generated %s (%d splats)" % [path, count])


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--splats="):
			_splats = maxi(1, int(arg.trim_prefix("--splats=")))
		elif arg.begins_with("--duration="):
			_duration = maxf(1.0, float(arg.trim_prefix("--duration=")))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
