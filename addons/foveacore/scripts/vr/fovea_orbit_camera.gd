extends Node
class_name FoveaOrbitCamera

## FoveaOrbitCamera — Script de caméra orbitale de secours pour le mode Desktop.
## Se place sous une Camera3D / XRCamera3D et manipule sa position/orientation.

@export var target := Vector3(0.0, 1.5, 0.0) # Cible de l'orbite
@export var distance := 5.0 # Distance par rapport à la cible
@export var rotation_speed := 0.25 # Sensibilité de la rotation
@export var zoom_speed := 0.5 # Sensibilité du zoom
@export var pan_speed := 3.0 # Vitesse de déplacement (pan)

var yaw := 0.0 # Angle horizontal (degrés)
var pitch := 20.0 # Angle vertical (degrés)
var _is_active := false

func _ready() -> void:
	# Initialiser les angles de rotation par rapport à la position courante du parent
	var cam = get_parent() as Camera3D
	if cam:
		_is_active = true
		var dir = cam.global_position - target
		distance = dir.length()
		yaw = rad_to_deg(atan2(dir.x, dir.z))
		pitch = rad_to_deg(asin(clamp(dir.y / distance, -0.99, 0.99)))
		print("FoveaOrbitCamera: Caméra orbitale de secours activée. Clic-droit pour tourner, Molette pour zoomer, ZQSD/Flèches pour déplacer.")
	else:
		_is_active = false
		push_warning("FoveaOrbitCamera: Le parent de ce nœud doit être de type Camera3D.")

func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return

	if event is InputEventMouseButton:
		# Zoom avec la molette
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				distance = max(1.0, distance - zoom_speed)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				distance = min(100.0, distance + zoom_speed)
				get_viewport().set_input_as_handled()
		
		# Clic droit pour capturer la souris et pivoter
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Pivoter avec les mouvements de souris
		yaw -= event.relative.x * rotation_speed
		pitch -= event.relative.y * rotation_speed
		pitch = clamp(pitch, -85.0, 85.0)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _is_active:
		return

	var cam = get_parent() as Camera3D
	if not cam:
		return

	# Déplacement de la cible de mise au point (Panning)
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_Z):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0

	if input_dir != Vector3.ZERO:
		var forward = -cam.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right = cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()

		var move_vec = (forward * input_dir.z + right * input_dir.x).normalized() * pan_speed * delta
		target += move_vec

	# Calculer la nouvelle position sphérique
	var pitch_rad = deg_to_rad(pitch)
	var yaw_rad = deg_to_rad(yaw)

	var offset = Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * distance

	cam.global_position = target + offset
	cam.look_at(target, Vector3.UP)
