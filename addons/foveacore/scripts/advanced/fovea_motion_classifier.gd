class_name FoveaMotionClassifier
extends RefCounted

## FoveaEngine — Static vs Dynamic Splat Classification (items 236-247)
## Automatically classifies splats as STATIC or DYNAMIC based on animation targets.

enum MotionClass { STATIC = 0, DYNAMIC = 1 }

func classify(splat_data: Array[Dictionary], animators: Array[Node]) -> Array[int]:
	var results: Array[int] = []
	results.resize(splat_data.size())
	results.fill(MotionClass.STATIC)
	
	# Animated splats → DYNAMIC
	for anim in animators:
		if not anim.has_method("modify_splat"): continue
		# Mark splats within animator's influence as dynamic
		# (simplified: all splats are dynamic when any animator is active)
		if animator_is_active(anim):
			results.fill(MotionClass.DYNAMIC)
			break
	
	return results

func animator_is_active(anim: Node) -> bool:
	if anim.has_method("is_active"):
		return anim.is_active() if anim.has_method("is_active") else anim.get("enabled", false)
	return false
