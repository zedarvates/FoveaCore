@tool
extends PanelContainer

var _playing: bool = true
var _time: float = 0.0

@onready var play_btn: Button = $VBoxContainer/PlayPause/PlayBtn
@onready var pause_btn: Button = $VBoxContainer/PlayPause/PauseBtn
@onready var scrub: HSlider = $VBoxContainer/Scrub
@onready var time_label: Label = $VBoxContainer/TimeLabel
@onready var anim_list: ItemList = $VBoxContainer/AnimatorList

func _ready() -> void:
	play_btn.pressed.connect(_on_play)
	pause_btn.pressed.connect(_on_pause)
	scrub.drag_ended.connect(_on_scrub)
	_refresh()

func _process(delta: float) -> void:
	if not _playing: return
	_time += delta
	scrub.value = fmod(_time, scrub.max_value)
	time_label.text = "t = %.2fs" % _time

func _on_play() -> void: _playing = true
func _on_pause() -> void: _playing = false
func _on_scrub(val_changed: bool) -> void:
	_time = scrub.value
	time_label.text = "t = %.2fs" % _time

func _refresh() -> void:
	anim_list.clear()
	var subs = get_tree().get_nodes_in_group("fovea_animators")
	for s in subs:
		anim_list.add_item(s.name + " (" + s.get_class() + ")")
