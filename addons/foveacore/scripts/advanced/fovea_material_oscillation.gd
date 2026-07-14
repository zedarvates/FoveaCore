extends Node3D
class_name FoveaMaterialOscillation

## Typed, non-destructive material and opacity modulation for transient splats.
@export_range(0.0, 1.0) var color_amplitude: float = 0.1
@export_range(0.0, 1.0) var opacity_amplitude: float = 0.2
@export_range(0.01, 10.0) var frequency: float = 1.5
@export var base_color: Color = Color.WHITE
@export var target_color: Color = Color(0.5, 0.5, 1.0, 1.0)

var _modifier_callable: Callable

func _ready() -> void:

	_modifier_callable = _apply_to_splat
	var manager: Node = _find_manager()
	if manager:
		var animation: FoveaAnimationSubsystem = manager.get_animation_subsystem()
		if animation:
			animation.register_modifier(_modifier_callable)

func _exit_tree() -> void:

	var manager: Node = _find_manager()
	if manager:
		var animation: FoveaAnimationSubsystem = manager.get_animation_subsystem()
		if animation:
			animation.unregister_modifier(_modifier_callable)

func _find_manager() -> Node:

	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("FoveaCoreManager")

func _apply_to_splat(splat: GaussianSplat, time: float, global_intensity: float) -> void:

	var phase: float = time * frequency * TAU
	var color_factor: float = (sin(phase) * 0.5 + 0.5) * color_amplitude * global_intensity
	var target: Color = base_color.lerp(target_color, color_factor)
	splat.color = splat.color.lerp(target, color_amplitude)
	var opacity_factor: float = 1.0 - opacity_amplitude * 0.5 + sin(phase * 1.3) * opacity_amplitude * 0.5
	splat.opacity *= clampf(opacity_factor, 0.0, 1.0)
