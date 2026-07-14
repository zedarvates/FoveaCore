extends Node3D
class_name FoveaNeuralOffsetAnimator

## FoveaNeuralOffsetAnimator — Phase 7.5 Neural Offset Field, runtime side.
## Registers a modifier on FoveaAnimationSubsystem that samples a
## FoveaNeuralOffsetField (baked offline, see that file's docstring) and adds
## the result to splat.position, same additive/log-space-safe pattern as the
## other Phase 7 animators. No inference happens here — purely a lookup.

@export var field: FoveaNeuralOffsetField = null
@export_range(0.0, 4.0) var amplitude: float = 1.0
@export var default_layer_weight: float = 1.0
@export var layer_weights: Dictionary = {}

var _modifier_callable: Callable

func _ready() -> void:
	_modifier_callable = _apply_to_splat
	var mgr := _find_manager()
	if mgr:
		var anim: FoveaAnimationSubsystem = mgr.get_animation_subsystem()
		if anim:
			anim.register_modifier(_modifier_callable)

func _exit_tree() -> void:
	var mgr := _find_manager()
	if mgr:
		var anim: FoveaAnimationSubsystem = mgr.get_animation_subsystem()
		if anim:
			anim.unregister_modifier(_modifier_callable)

func _find_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("FoveaCoreManager")

func _apply_to_splat(splat: GaussianSplat, time: float, global_intensity: float) -> void:
	if field == null:
		return
	var weight: float = layer_weights.get(splat.layer_type, default_layer_weight)
	if weight <= 0.0:
		return
	var offset: Vector3 = field.sample(splat.position, time)
	splat.position += offset * amplitude * weight * global_intensity
