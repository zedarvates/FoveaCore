extends Node3D
class_name FoveaFlowFieldAnimator

## FoveaFlowFieldAnimator — Phase 7.1 Flow-Driven Animation.
## Generalizes the advection concept already used in water_splat_particle.gdshader
## (flow_direction / flow_speed) to any splat set, as a registered modifier on
## FoveaAnimationSubsystem. Displacement is expressed as a pure function of
## world time (not integrated velocity), so it stays correct even though
## current_splats is rebuilt from source every frame (no persistent GPU state
## to advect/recycle at this CPU pipeline stage — see docs/RD_SPLATS_ANIMES_ROADMAP.md).
##
## Presets:
##   WIND    — pseudo-curl noise displacement (foliage, cloth, smoke)
##   BREATHE — radial sinusoidal pulse around the node's origin
##   CURRENT — advection along hand-painted flow direction (stored in splat.normal by SplatBrush)

enum Preset { WIND, BREATHE, CURRENT }

@export var preset: Preset = Preset.WIND
@export_range(0.0, 2.0) var amplitude: float = 0.15
@export_range(0.01, 5.0) var frequency: float = 0.5
## World-space origin used by BREATHE. Defaults to this node's global position.
@export var origin_override: Vector3 = Vector3.ZERO
@export var use_node_origin: bool = true

## Per-layer amplitude multiplier. Missing layers default to [member default_layer_weight].
@export var default_layer_weight: float = 1.0
@export var layer_weights: Dictionary = {
	GaussianSplat.LayerType.LEAVES: 1.0,
	GaussianSplat.LayerType.LIQUID: 1.0,
	GaussianSplat.LayerType.SHADOW: 0.5,
}

var _noise := FastNoiseLite.new()
var _modifier_callable: Callable

func _ready() -> void:
	_noise.seed = int(get_instance_id() % 100000)
	_noise.frequency = 0.5
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
	var offset: Vector3
	match preset:
		Preset.BREATHE:
			offset = _breathe_offset(splat.position, time)
		Preset.CURRENT:
			offset = _current_offset(splat, time)
		_:
			offset = _wind_offset(splat.position, time)
	splat.position += offset * amplitude * weight * global_intensity

func _current_offset(splat: GaussianSplat, time: float) -> Vector3:
	if splat.normal.length_squared() < 0.001:
		return Vector3.ZERO
	var pulse := sin(time * frequency * TAU)
	return splat.normal.normalized() * pulse

func _wind_offset(pos: Vector3, time: float) -> Vector3:
	# Pseudo-curl noise: FastNoiseLite has no 4D sampling in Godot 4, so time is
	# encoded as a scrolling offset on each axis (with distinct large constants
	# per axis to decorrelate the three samples and avoid uniform translation).
	var t := time * frequency
	var nx := _noise.get_noise_3d(pos.x, pos.y, pos.z + t * 4.11)
	var ny := _noise.get_noise_3d(pos.x + 37.2, pos.y + 11.7 + t * 3.73, pos.z)
	var nz := _noise.get_noise_3d(pos.x + t * 2.97, pos.y + 71.3, pos.z + 19.4)
	return Vector3(nx, ny, nz)

func _breathe_offset(pos: Vector3, time: float) -> Vector3:
	var origin := global_position if use_node_origin else origin_override
	var dir := pos - origin
	var dist := dir.length()
	if dist < 0.0001:
		return Vector3.ZERO
	var pulse := sin(time * frequency * TAU + dist * 0.5)
	return (dir / dist) * pulse
