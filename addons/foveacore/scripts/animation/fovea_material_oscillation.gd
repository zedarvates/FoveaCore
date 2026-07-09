class_name FoveaMaterialOscillation
extends Node3D

## FoveaEngine — Material Oscillation
## Animates splat color, opacity, emission over time.

@export var enabled: bool = true
@export var color_amplitude: float = 0.1
@export var opacity_amplitude: float = 0.2
@export var emission_amplitude: float = 0.3
@export var frequency: float = 1.5
@export var base_color: Color = Color.WHITE
@export var target_color: Color = Color(0.5, 0.5, 1.0, 1.0)

func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
	var t = subsystem.anim_time * frequency
	var factor = sin(t) * 0.5 + 0.5
	
	# Color oscillation
	var col = base_color.lerp(target_color, factor * color_amplitude)
	splat["color"] = col
	
	# Opacity oscillation
	var alpha = 1.0 - opacity_amplitude * 0.5 + sin(t * 1.3) * opacity_amplitude * 0.5
	splat["color"].a = clamp(alpha, 0.0, 1.0)
	
	return splat

func apply_animation(subsystem: FoveaAnimationSubsystem, delta: float) -> void:
	pass  # CPU path handled per-splat via modify_splat
