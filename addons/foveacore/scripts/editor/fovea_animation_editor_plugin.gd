@tool
extends EditorPlugin
var _dock: Control = null
func _enter_tree() -> void:
	_dock = preload("res://addons/foveacore/scenes/animation_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock, "Animation")
func _exit_tree() -> void:
	if _dock: remove_control_from_docks(_dock); _dock.queue_free()
