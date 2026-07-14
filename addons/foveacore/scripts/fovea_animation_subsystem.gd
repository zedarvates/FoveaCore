class_name FoveaAnimationSubsystem
extends Node

## FoveaAnimationSubsystem — Phase 7.0 foundation for Dynamic Splat Animation.
## Applies additive, non-destructive per-frame offsets to the transient
## Array[GaussianSplat] produced each frame by FoveaSplatSubsystem.
##
## Non-destructive by construction: current_splats is rebuilt from
## FoveaSplattable.loaded_splats every frame, so this subsystem never
## mutates source data — only the transient render-frame copy.
##
## Modes registered here (ANIM_FLOW, ANIM_MORPH_COVARIANCE, ANIM_LAYER,
## ANIM_STRETCH, ...) are added by later sub-phases (7.1-7.6). Phase 7.0
## only wires the pass point and time tracking.

signal animation_toggled(enabled: bool)

@export var enabled: bool = true:
	set(value):
		enabled = value
		animation_toggled.emit(enabled)
@export_range(0.0, 4.0) var global_intensity: float = 1.0

## Registered per-splat animation modifiers, applied in order.
## Each modifier is a Callable(splat: GaussianSplat, time: float, intensity: float) -> void
var _modifiers: Array[Callable] = []

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta

## Registers an animation modifier callable. Later sub-phases call this to
## plug in flow fields, covariance morphing, etc.
func register_modifier(modifier: Callable) -> void:
	if not _modifiers.has(modifier):
		_modifiers.append(modifier)

func unregister_modifier(modifier: Callable) -> void:
	_modifiers.erase(modifier)

## Applies all registered modifiers to the given frame's splats in place.
## Called by FoveaSplatSubsystem before depth-sort so animated positions
## are used for sorting and foveated weighting.
func apply(splats: Array[GaussianSplat]) -> void:
	if not enabled or _modifiers.is_empty():
		return
	for splat: GaussianSplat in splats:
		for modifier: Callable in _modifiers:
			modifier.call(splat, _time, global_intensity)

func get_time() -> float:
	return _time
