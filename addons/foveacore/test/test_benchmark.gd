extends SceneTree
## Timer microbenchmark smoke test (items 335-350).
## This does not load or render splats and must not be used as engine performance evidence.
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== Timer Microbenchmark Smoke Test ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var samples: Array[float] = []
	for _sample in range(3):
		var start = Time.get_ticks_usec()
		for _i in range(100):
			pass
		samples.append(float(Time.get_ticks_usec() - start) / 100.0)
	var all_valid := true
	for elapsed_us in samples:
		all_valid = all_valid and elapsed_us >= 0.0
	if all_valid:
		_passed += 1
		print("  ✓ Timer produced %d non-negative loop samples" % samples.size())
	else:
		_failed += 1
		push_error("  ✗ Timer produced an invalid sample")
	print("  %d/%d" % [_passed, _passed + _failed])
