class_name Fovea4DPlayer
extends Node

const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")

signal motion_loaded(sidecar_path: String)
signal motion_error(message: String)

enum LoopOverride { USE_SIDECAR, FORCE_LOOP, FORCE_ONCE }

@export var target_path: NodePath
@export_file("*.fovea4d") var sidecar_path: String = ""
@export var autoplay: bool = true
@export var playback_rate: float = 1.0
@export var loop_override: LoopOverride = LoopOverride.USE_SIDECAR

var playing: bool = false
var time_seconds: float = 0.0
var last_error: String = ""
var _target: FoveaSplat3D = null
var _delegate: FoveaSplattable = null


func _ready() -> void:
	playing = autoplay
	call_deferred("_load_motion_deferred")


func _exit_tree() -> void:
	if _delegate != null:
		_delegate.clear_4d_motion()
	_delegate = null
	_target = null


func _process(delta: float) -> void:
	if not playing or _delegate == null or not is_finite(delta):
		return
	time_seconds += delta * playback_rate
	_delegate.update_4d_motion_time(time_seconds)


func load_motion_now() -> Error:
	last_error = ""
	var candidate: Node = get_node_or_null(target_path)
	if not candidate is FoveaSplat3D:
		return _fail("target_path must reference a FoveaSplat3D", ERR_INVALID_PARAMETER)
	_target = candidate as FoveaSplat3D
	_delegate = _target.get_advanced()
	if _delegate == null:
		return _fail("target delegate is not ready", ERR_UNAVAILABLE)
	if sidecar_path.is_empty():
		return _fail("sidecar_path is required", ERR_INVALID_PARAMETER)
	if _target.source_path.is_empty():
		return _fail("target source_path is required", ERR_INVALID_PARAMETER)
	var result: Dictionary = LoaderScript.load_sidecar(sidecar_path, _target.source_path)
	if not bool(result.get("ok", false)):
		return _fail(str(result.get("error", "motion load failed")), ERR_FILE_CORRUPT)
	var field: Fovea4DMotionField = result.get("field")
	if loop_override == LoopOverride.FORCE_LOOP:
		field.loop = true
	elif loop_override == LoopOverride.FORCE_ONCE:
		field.loop = false
	var configure_error: Error = _delegate.configure_4d_motion(field)
	if configure_error != OK:
		return _fail("target rejected 4D motion: %s" % error_string(configure_error), configure_error)
	time_seconds = 0.0
	_delegate.update_4d_motion_time(time_seconds)
	motion_loaded.emit(sidecar_path)
	return OK


func play() -> void:
	playing = true


func pause() -> void:
	playing = false


func seek(value: float) -> void:
	if not is_finite(value):
		return
	time_seconds = value
	if _delegate != null:
		_delegate.update_4d_motion_time(time_seconds)


func _load_motion_deferred() -> void:
	var error: Error = load_motion_now()
	if error != OK:
		playing = false


func _fail(message: String, error: Error) -> Error:
	last_error = message
	motion_error.emit(message)
	if _delegate != null:
		_delegate.clear_4d_motion()
	return error
