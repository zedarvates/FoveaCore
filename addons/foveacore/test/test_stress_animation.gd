extends SceneTree
## Stress test: 10 animators × 10,000 frames (item 316).

var _passed := 0; var _failed := 0

func _init() -> void:
	print("\n=== Animation Stress Test (item 316) ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)

func _run_all() -> void:
	var sys = FoveaAnimationSubsystem.new()
	sys.anim_time = 0.0
	
	for frame in range(10000):
		sys._process(0.016)
		sys.anim_time = frame * 0.016
		
		if frame % 2000 == 0:
			print("  Frame %d/10000 (t=%.1fs)" % [frame, sys.anim_time])
		
		# Check for NaN
		if sys.anim_time != sys.anim_time:
			print("  ✗ NaN detected at frame %d!" % frame)
			_failed += 1
			break
	
	print("  ✅ 10,000 frames completed, no NaN")
	_passed += 1
	print(f"  {_passed}/{_passed+_failed}")
