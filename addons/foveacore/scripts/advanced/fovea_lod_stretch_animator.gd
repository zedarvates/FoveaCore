extends Node3D
class_name FoveaLodStretchAnimator

## FoveaLodStretchAnimator — Phase 7.4 (LOD Stretch half). Cartoon-style
## squash & stretch: isotropic size oscillation driven by time, reusing the
## same registered-modifier pattern as the Phase 7.1/7.2 animators.
##
## Uses a log-space multiplicative factor (exp(amplitude * sin(...))) for the
## same reason as FoveaMorphCovarianceAnimator: scale must never cross zero.
##
## Foveation-aware cutoff (skip animation outside the gaze fovea, per the
## roadmap) is deferred: the per-splat modifier signature (splat, time,
## intensity) has no camera/viewport context to project world position to
## screen space, and the gaze uniforms (fovea_gaze_left/right) are consumed
## GPU-side today. Doing this properly means either passing a camera
## reference into FoveaAnimationSubsystem.apply() or moving this animator to
## the GPU compute pass — tracked as follow-up work alongside the Phase 7.1/7.2
## GPU ports.

@export_range(0.0, 1.0) var amplitude: float = 0.1
@export_range(0.01, 5.0) var frequency: float = 2.0

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
	var weight: float = layer_weights.get(splat.layer_type, default_layer_weight)
	if weight <= 0.0:
		return
	var phase: float = float(hash(splat.position) & 0xFFFF) / float(0xFFFF) * TAU
	var factor: float = exp(amplitude * weight * global_intensity * sin(time * frequency * TAU + phase))
	splat.scale *= factor
	splat.compute_derived()
