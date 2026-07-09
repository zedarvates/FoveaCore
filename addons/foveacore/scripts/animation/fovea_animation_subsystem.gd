class_name FoveaAnimationSubsystem
extends Node

## FoveaEngine — Animation Subsystem
## Orchestrates all splat animation: flow, morph, oscillation, flipbook, LOD, neural, skinning.
## Acts as the coordinator — each animator registers here and gets called each frame.

enum AnimationMode { CPU = 0, GPU = 1, AUTO = 2 }

@export var enabled: bool = true
@export var animation_backend: AnimationMode = AnimationMode.CPU
@export var global_intensity: float = 1.0
@export var global_time_scale: float = 1.0

var anim_time: float = 0.0
var _animators: Array[Node] = []
var _camera: Camera3D = null

func _ready() -> void:
	# Auto-discover child animators
	for child in get_children():
		if child.has_method("apply_animation"):
			_animators.append(child)

func register_animator(animator: Node) -> void:
	if not animator in _animators:
		_animators.append(animator)

func unregister_animator(animator: Node) -> void:
	_animators.erase(animator)

func _process(delta: float) -> void:
	if not enabled or animation_backend == AnimationMode.GPU:
		return
	
	anim_time += delta * global_time_scale
	
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	
	for anim in _animators:
		if anim.has_method("apply_animation"):
			anim.apply_animation(self, delta)

func apply_to_splat(splat: Dictionary, delta: float) -> Dictionary:
	"""Apply all registered animations to a single splat (CPU path)."""
	var result = splat.duplicate()
	for anim in _animators:
		if anim.has_method("modify_splat"):
			result = anim.modify_splat(result, delta, self)
	return result
