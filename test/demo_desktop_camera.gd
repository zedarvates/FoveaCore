class_name DemoDesktopCamera
extends Camera3D

@export var move_speed: float = 5.0
@export var look_sensitivity: float = 0.15

var _rotation: Vector3 = Vector3.ZERO
var _mouse_captured: bool = false

func _ready() -> void:
	_rotation = rotation

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_mouse_captured = true
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_mouse_captured = false
				
	if event is InputEventMouseMotion and _mouse_captured:
		_rotation.y -= event.relative.x * deg_to_rad(look_sensitivity)
		_rotation.x -= event.relative.y * deg_to_rad(look_sensitivity)
		_rotation.x = clamp(_rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
		rotation = _rotation

func _process(delta: float) -> void:
	var move_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		move_dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		move_dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		move_dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		move_dir -= global_transform.basis.y
	if Input.is_key_pressed(KEY_E):
		move_dir += global_transform.basis.y
		
	if move_dir.length_squared() > 0.0:
		global_position += move_dir.normalized() * move_speed * delta
