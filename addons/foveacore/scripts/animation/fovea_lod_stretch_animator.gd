class_name FoveaLodStretchAnimator
extends Node3D

## FoveaEngine — LOD Stretch Animator
## Stretches splat scale based on distance from camera (LOD-dependent).

@export var enabled: bool = true
@export var stretch_curve: Curve = null
@export var max_stretch: float = 2.0
@export var lod_bias: float = 1.0

func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
	if not enabled:
		return splat
	
	var camera = subsystem._camera
	if camera == null:
		return splat
	
	var pos = splat.get("position", Vector3.ZERO)
	var dist = camera.global_position.distance_to(pos)
	var lod_factor = clamp(dist / 10.0, 0.0, 1.0)
	
	var stretch = 1.0
	if stretch_curve:
		stretch = 1.0 + stretch_curve.sample(lod_factor) * (max_stretch - 1.0)
	else:
		stretch = 1.0 + lod_factor * (max_stretch - 1.0)
	
	stretch *= lod_bias
	var s = splat.get("scale", Vector3.ONE)
	splat["scale"] = Vector3(s.x * stretch, s.y, s.z * stretch)
	return splat

func apply_animation(subsystem: FoveaAnimationSubsystem, delta: float) -> void:
	pass
