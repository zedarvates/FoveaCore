@tool
extends Label
## Tiny on-screen FPS / splat readout for the "Drop a PLY" demo scene.

func _process(_delta: float) -> void:
	text = "FPS: %d" % Engine.get_frames_per_second()
