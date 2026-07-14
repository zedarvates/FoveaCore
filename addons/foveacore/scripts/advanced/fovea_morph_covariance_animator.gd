extends Node3D
class_name FoveaMorphCovarianceAnimator

## FoveaMorphCovarianceAnimator — Phase 7.2 Morph Covariance Animation.
##
## Animates the Gaussian's shape (scale + rotation) itself rather than just its
## position — pulsation, anisotropic breathing, and rotational wobble. In this
## engine's CPU splat representation, [member GaussianSplat.covariance] is a
## simplified 2D value *derived* from [member GaussianSplat.scale] via
## [method GaussianSplat.compute_derived] — so "morphing Σ" here means
## animating scale/rotation and re-deriving covariance every frame, which is
## the CPU-pipeline equivalent of morphing the true 3x3 covariance matrix.
##
## Correctness requirement (do not regress): naive linear interpolation of an
## anisotropic scale can pass through zero/negative values and flip the
## ellipse inside-out. All scale animation here is therefore MULTIPLICATIVE
## in log-space (factor = exp(amplitude * f(t))), never additive/linear —
## this keeps scale strictly positive and matches how true covariance
## interpolation must be done (log-space for the scale part, slerp for the
## rotation part; see roadmap Phase 7.2 for the full 3x3 justification).
##
## Because current_splats is rebuilt from source every frame (see Phase 7.0
## notes), there is no persistent per-splat animation phase to carry across
## frames. Each splat's phase/axis is instead derived deterministically from
## a hash of its base position, which desynchronizes splats without state
## (per-splat phase via hash(splat_id), as specified in the roadmap).
##
## MORPH (authored Σ_base → Σ_target via a SplatBrush "covariance target"
## tool) is deferred — it needs an authoring workflow, not just a modifier
## (same deferral rationale as CURRENT in Phase 7.1).

enum Preset { PULSE, BREATHE, WOBBLE }

@export var preset: Preset = Preset.PULSE
## Log-space scale amplitude. factor = exp(amplitude * sin(...)); 0.15 ≈ ±16% size.
@export_range(0.0, 1.0) var amplitude: float = 0.15
@export_range(0.01, 5.0) var frequency: float = 1.0
## Max wobble rotation angle in degrees (WOBBLE preset only).
@export_range(0.0, 45.0) var wobble_max_angle_deg: float = 8.0

## Per-layer amplitude multiplier. Missing layers default to [member default_layer_weight].
@export var default_layer_weight: float = 1.0
@export var layer_weights: Dictionary = {
	GaussianSplat.LayerType.LIQUID: 1.0,
	GaussianSplat.LayerType.LEAVES: 0.6,
}

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

## Deterministic per-splat phase in [0, TAU), derived from base position so
## it stays stable across frames without any persistent per-splat state.
static func _phase_for_splat(splat: GaussianSplat) -> float:
	var h: int = hash(splat.position)
	return float(h & 0xFFFF) / float(0xFFFF) * TAU

## Deterministic per-splat unit rotation axis, derived the same way as the phase.
static func _axis_for_splat(splat: GaussianSplat) -> Vector3:
	var h: int = hash(splat.position * 7.0 + Vector3(1.0, 2.0, 3.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if axis.length_squared() < 0.0001:
		return Vector3.UP
	return axis.normalized()

func _apply_to_splat(splat: GaussianSplat, time: float, global_intensity: float) -> void:
	var weight: float = layer_weights.get(splat.layer_type, default_layer_weight)
	if weight <= 0.0:
		return
	var effective_amp: float = amplitude * weight * global_intensity
	if effective_amp <= 0.0001:
		return
	var phase := _phase_for_splat(splat)

	match preset:
		Preset.BREATHE:
			_apply_breathe(splat, time, effective_amp, phase)
		Preset.WOBBLE:
			_apply_wobble(splat, time, effective_amp, phase)
		_:
			_apply_pulse(splat, time, effective_amp, phase)

	splat.compute_derived()

## Uniform log-space pulsation of the whole ellipsoid.
func _apply_pulse(splat: GaussianSplat, time: float, effective_amp: float, phase: float) -> void:
	var factor: float = exp(effective_amp * sin(time * frequency * TAU + phase))
	splat.scale *= factor

## Anisotropic, roughly volume-preserving breathing: the dominant axis expands
## while the other two contract slightly, then the cycle reverses.
func _apply_breathe(splat: GaussianSplat, time: float, effective_amp: float, phase: float) -> void:
	var s := sin(time * frequency * TAU + phase)
	var dominant_axis := 0
	if splat.scale.y > splat.scale[dominant_axis]:
		dominant_axis = 1
	if splat.scale.z > splat.scale[dominant_axis]:
		dominant_axis = 2

	var expand_factor: float = exp(effective_amp * s)
	var contract_factor: float = exp(-0.5 * effective_amp * s)

	var new_scale := splat.scale
	for axis in range(3):
		new_scale[axis] *= expand_factor if axis == dominant_axis else contract_factor
	splat.scale = new_scale

## Small-angle rotational jitter around a per-splat pseudo-random axis.
func _apply_wobble(splat: GaussianSplat, time: float, effective_amp: float, phase: float) -> void:
	var axis := _axis_for_splat(splat)
	var max_angle: float = deg_to_rad(wobble_max_angle_deg) * effective_amp / max(amplitude, 0.0001)
	var angle: float = max_angle * sin(time * frequency * TAU + phase)
	var jitter := Quaternion(axis, angle)
	splat.rotation = (jitter * splat.rotation).normalized()
