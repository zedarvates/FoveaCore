class_name FoveaFlipbookAnimator
extends Node3D

## FoveaEngine — Flipbook Animator
## Plays through a sequence of splat frames (e.g. captured from video).

@export var enabled: bool = true
@export var fps: float = 12.0
@export var frame_count: int = 1
@export var loop: bool = true
@export var crossfade: bool = true

var _current_frame: int = 0
var _frame_time: float = 0.0

func apply_animation(subsystem: FoveaAnimationSubsystem, delta: float) -> void:
	if not enabled or frame_count <= 1:
		return
	
	_frame_time += delta
	var frame_duration = 1.0 / max(fps, 0.001)
	
	if _frame_time >= frame_duration:
		_frame_time -= frame_duration
		_current_frame += 1
		if _current_frame >= frame_count:
			_current_frame = 0 if loop else frame_count - 1

func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
	splat["flipbook_frame"] = _current_frame
	splat["flipbook_frame_count"] = frame_count
	if crossfade:
		splat["flipbook_blend"] = _frame_time * fps
	return splat
