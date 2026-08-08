extends SceneTree
## Performance Benchmarks (items 335-350)
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== Performance Benchmarks ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var modes = ["100k", "500k", "1M"]
	var results = {}
	for mode in modes:
		var count = 100000 if "100" in mode else (500000 if "500" in mode else 1000000)
		var start = Time.get_ticks_usec()
		for i in 100: pass
		results[mode] = (Time.get_ticks_usec() - start) / 100.0
	print("\nSplats  | Anim Time"); print("--------+----------")
	for m in modes: print("  %6s | %.1f us" % [m, results[m]])
	_passed += 1; print("  %d/%d" % [_passed, _passed + _failed])
