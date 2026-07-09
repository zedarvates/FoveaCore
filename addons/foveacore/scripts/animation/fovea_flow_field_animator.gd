class_name FoveaFlowFieldAnimator
extends Node3D

## FoveaEngine — Flow Field Animator
## Curl-noise driven flow animation. Simulates wind, water currents, organic movement.

enum Preset { WIND = 0, WATER = 1, ORGANIC = 2, CUSTOM = 3 }

@export var enabled: bool = true
@export var preset: Preset = Preset.WIND:
	set(v):
		preset = v
		_apply_preset()
@export var amplitude: float = 0.3
@export var frequency: float = 0.5
@export var speed: float = 1.0
@export var turbulence: float = 0.2
@export var layer_weights: Dictionary = {}  # layer_name → weight
@export var influence_radius: float = 10.0

var _noise: FastNoiseLite = FastNoiseLite.new()

func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.05
	_apply_preset()

func _apply_preset() -> void:
	match preset:
		Preset.WIND:
			amplitude = 0.3; frequency = 0.5; speed = 1.0; turbulence = 0.2
		Preset.WATER:
			amplitude = 0.15; frequency = 0.3; speed = 0.5; turbulence = 0.4
		Preset.ORGANIC:
			amplitude = 0.2; frequency = 0.2; speed = 0.3; turbulence = 0.1

func apply_animation(subsystem: FoveaAnimationSubsystem, delta: float) -> void:
	if not enabled:
		return
	var t = subsystem.anim_time * speed
	
	# Curl-noise displacement: use noise derivatives for divergence-free flow
	for child in get_parent().get_children():
		if child.has_method("get_splat_count") and child.get("instance_count", 0) > 0:
			var n = child.instance_count if child.has_method("get_instance_count") else child.get("instance_count", 0)
			# Apply per-instance — actual implementation would modify the GPU buffer
			pass

func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
	"""Modify a single splat position using curl-noise."""
	var t = subsystem.anim_time * speed
	var pos = splat.get("position", Vector3.ZERO)
	
	# Curl-noise: 3D noise → divergence-free vector field
	var nx = _noise.get_noise_3d(pos.x + t, pos.y, pos.z) * amplitude
	var ny = _noise.get_noise_3d(pos.x, pos.y + t, pos.z) * amplitude
	var nz = _noise.get_noise_3d(pos.x, pos.y, pos.z + t) * amplitude
	
	var offset = Vector3(ny - nz, nz - nx, nx - ny) * turbulence
	offset += Vector3(cos(pos.y * frequency + t), sin(pos.z * frequency + t), cos(pos.x * frequency + t)) * amplitude * (1.0 - turbulence)
	
	# Apply layer weight
	var layer = splat.get("layer", 0)
	var weight = layer_weights.get(str(layer), 1.0)
	
	splat["position"] = pos + offset * weight * subsystem.global_intensity
	return splat
