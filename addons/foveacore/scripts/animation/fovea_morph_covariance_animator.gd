class_name FoveaMorphCovarianceAnimator
extends Node3D

## FoveaEngine — Morph Covariance Animator
## Interpolates between base and target covariance matrices (breathing, pulsing).

enum MorphType { PULSE = 0, BREATHE = 1, WOBBLE = 2, CUSTOM = 3 }

@export var enabled: bool = true
@export var morph_type: MorphType = MorphType.BREATHE
@export var amplitude: float = 0.3
@export var frequency: float = 1.0
@export var phase_offset: float = 0.0

func apply_animation(subsystem: FoveaAnimationSubsystem, delta: float) -> void:
	if not enabled:
		return
	var t = subsystem.anim_time * frequency + phase_offset
	var factor = sin(t) * amplitude
	
	match morph_type:
		MorphType.PULSE:
			# Uniform scaling in log-space
			_apply_pulse(factor)
		MorphType.BREATHE:
			# Extend dominant axis, contract minor axes
			_apply_breathe(factor, t)
		MorphType.WOBBLE:
			# Per-splat quaternion jitter
			_apply_wobble(factor, t)

func _apply_pulse(factor: float) -> void:
	pass  # Would scale covariance uniform for all splats

func _apply_breathe(factor: float, t: float) -> void:
	pass  # Would extend dominant axis

func _apply_wobble(factor: float, t: float) -> void:
	pass  # Would rotate per-splat with hashed axis

func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
	var t = subsystem.anim_time * frequency + phase_offset
	var factor = sin(t) * amplitude
	
	var scale = splat.get("scale", Vector3.ONE)
	var rot = splat.get("rotation", Quaternion.IDENTITY)
	
	match morph_type:
		MorphType.PULSE:
			var log_factor = 1.0 + factor
			splat["scale"] = scale * log_factor
		MorphType.BREATHE:
			var dominant = max(scale.x, max(scale.y, scale.z))
			var axis = 0 if scale.x == dominant else 1 if scale.y == dominant else 2
			var v = scale
			v[axis] *= 1.0 + factor
			v[(axis+1)%3] *= 1.0 - factor * 0.5
			v[(axis+2)%3] *= 1.0 - factor * 0.5
			splat["scale"] = v
		MorphType.WOBBLE:
			var hash_angle = hash(splat.get("instance_id", 0)) * 0.001
			var wobble = Quaternion(Vector3.UP, factor * 0.5 * sin(t + hash_angle))
			splat["rotation"] = rot * wobble
	
	return splat
