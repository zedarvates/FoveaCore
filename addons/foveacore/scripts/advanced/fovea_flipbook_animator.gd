extends Node3D
class_name FoveaFlipbookAnimator

## FoveaFlipbookAnimator — Phase 7.3 LAYER_ANIM / Temporal Flipbook.
##
## Splats tagged with GaussianSplat.flipbook_frame >= 0 belong to a temporal
## sequence of [member flipbook_frame_count] frames (e.g. one .fovea asset per
## frame of a captured flame or magic effect, cf. roadmap Phase 7.3). This
## animator selects the active frame from [member fps] and mutes every other
## frame's opacity to zero, so only one frame renders per splat group at a
## time — the render cost of inactive frames is a cull, not a draw, matching
## the "flipbook is nearly free" rationale in the roadmap.
##
## Crossfade blends opacity between the current and next frame across the
## frame boundary for smoother low-fps flipbooks (optional, off by default to
## keep the default behavior a hard cut matching the roadmap's baseline spec).
##
## Splats with flipbook_frame == -1 (the default) are entirely untouched —
## this animator only ever affects explicitly tagged flipbook splats.
##
## Frame authoring (importing a folder of .ply/.fovea frames as one flipbook,
## tagging flipbook_frame/flipbook_frame_count on load) is a fovea_asset_loader.gd
## extension, deferred — out of scope for the animation-subsystem modifier
## itself (same deferral pattern as MORPH's authoring tool in 7.2).

@export_range(0.1, 60.0) var fps: float = 12.0
@export var crossfade_enabled: bool = false

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
	if splat.flipbook_frame < 0 or splat.flipbook_frame_count <= 0:
		return

	var cycle_pos: float = fmod(time * fps, float(splat.flipbook_frame_count))
	if cycle_pos < 0.0:
		cycle_pos += float(splat.flipbook_frame_count)
	var active_frame: int = int(floor(cycle_pos))

	if crossfade_enabled:
		var frac: float = cycle_pos - float(active_frame)
		var next_frame: int = (active_frame + 1) % splat.flipbook_frame_count
		if splat.flipbook_frame == active_frame:
			splat.opacity *= (1.0 - frac) * global_intensity
		elif splat.flipbook_frame == next_frame:
			splat.opacity *= frac * global_intensity
		else:
			splat.opacity = 0.0
	else:
		if splat.flipbook_frame == active_frame:
			splat.opacity *= global_intensity
		else:
			splat.opacity = 0.0
