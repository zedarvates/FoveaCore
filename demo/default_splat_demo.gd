extends Node3D

## Prefer the locally validated real-camera reconstruction. It remains
## gitignored because the source footage is not redistributable. Public clones
## fall back to the checked-in CC0 synthetic-video reconstruction.
@export_file("*.ply") var real_capture_source_path: String = \
	"res://reconstructions/furby_real_60_v1/fovea_runtime/furby_6999_runtime_foreground_v1.ply"
@export_file("*.ply") var redistributable_source_path: String = \
	"res://reconstructions/horse_statue_cc0_v1/fovea_runtime/horse_statue_6999_runtime_v1.ply"
@export_file("*.ply") var compatibility_fixture_path: String = \
	"res://test/fixtures/reference_3dgs.ply"

enum SourceKind {
	REAL_CAMERA_VIDEO,
	SYNTHETIC_VIDEO,
	COMPATIBILITY_FIXTURE,
}

const REAL_CAMERA_FOV_DEG: float = 45.239728
const REAL_CAMERA_TRANSFORM: Transform3D = Transform3D(
	Basis(
		Vector3(-0.23200420, -0.95911753, 0.16207299),
		Vector3(-0.97225553, 0.22353357, -0.06893434),
		Vector3(0.02988738, -0.17356943, -0.98436803)
	),
	Vector3(-0.07474361, -0.13341911, -1.03964865)
)
const REAL_ORBIT_TARGET: Vector3 = Vector3(-0.12226, -0.04649, -0.02985)
const SYNTHETIC_CAMERA_FOV_DEG: float = 42.0
const SYNTHETIC_CAMERA_POSITION: Vector3 = Vector3(0.15477, 0.204318, 1.140705)
const SYNTHETIC_ORBIT_TARGET: Vector3 = Vector3(0.15477, 0.004619, 0.008201)
var _source_kind: SourceKind = SourceKind.COMPATIBILITY_FIXTURE
var _camera: Camera3D = null
var _orbit_target: Vector3 = Vector3.ZERO
var _orbit_distance: float = 1.0
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.0
var _capture_path: String = ""


func _enter_tree() -> void:
	var splat: FoveaSplat3D = get_node("FoveaSplat3D") as FoveaSplat3D
	if FileAccess.file_exists(real_capture_source_path):
		_source_kind = SourceKind.REAL_CAMERA_VIDEO
		splat.source_path = real_capture_source_path
	elif FileAccess.file_exists(redistributable_source_path):
		_source_kind = SourceKind.SYNTHETIC_VIDEO
		splat.source_path = redistributable_source_path
	else:
		_source_kind = SourceKind.COMPATIBILITY_FIXTURE
		splat.source_path = compatibility_fixture_path


func _ready() -> void:
	_camera = get_node("Camera3D") as Camera3D
	var status: Label = get_node("HUD/SourceStatus") as Label
	if _source_kind == SourceKind.REAL_CAMERA_VIDEO:
		_camera.transform = REAL_CAMERA_TRANSFORM
		_camera.fov = REAL_CAMERA_FOV_DEG
		_orbit_target = REAL_ORBIT_TARGET
		status.text = "REAL CAMERA VIDEO 3DGS · 17,013 splats · local proof · drag LMB to orbit"
		status.modulate = Color(0.55, 1.0, 0.65)
		print("Drop a PLY: using real-camera video reconstruction: ", real_capture_source_path)
	elif _source_kind == SourceKind.SYNTHETIC_VIDEO:
		_camera.position = SYNTHETIC_CAMERA_POSITION
		_camera.look_at(SYNTHETIC_ORBIT_TARGET, Vector3.UP)
		_camera.fov = SYNTHETIC_CAMERA_FOV_DEG
		_orbit_target = SYNTHETIC_ORBIT_TARGET
		status.text = "SYNTHETIC VIDEO 3DGS · 25,674 splats · CC0 source · drag LMB to orbit"
		status.modulate = Color(0.55, 0.8, 1.0)
		print("Drop a PLY: real capture unavailable; using CC0 synthetic-video reconstruction: ", redistributable_source_path)
	else:
		_camera.transform = Transform3D(
			Basis.IDENTITY,
			Vector3(0.0, 1.2, 5.0)
		).looking_at(Vector3.ZERO, Vector3.UP)
		status.text = "COMPATIBILITY FIXTURE · no video reconstruction found"
		status.modulate = Color(1.0, 0.75, 0.35)
		push_warning(
			"Drop a PLY: real and synthetic video reconstructions are unavailable; "
			+ "showing the small parser fixture only."
		)
	_initialize_orbit()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--demo-capture="):
			_capture_path = arg.trim_prefix("--demo-capture=")
	if not _capture_path.is_empty():
		_capture_after_settle.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * 0.006
		_orbit_pitch = clampf(_orbit_pitch - motion.relative.y * 0.006, -1.35, 1.35)
		_update_orbit_camera()
	elif event is InputEventMouseButton and event.pressed:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(_orbit_distance * 0.9, 0.15)
			_update_orbit_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(_orbit_distance * 1.1, 20.0)
			_update_orbit_camera()


func _initialize_orbit() -> void:
	var offset: Vector3 = _camera.position - _orbit_target
	_orbit_distance = maxf(offset.length(), 0.15)
	var direction: Vector3 = offset / _orbit_distance
	_orbit_yaw = atan2(direction.x, direction.z)
	_orbit_pitch = asin(clampf(direction.y, -1.0, 1.0))


func _update_orbit_camera() -> void:
	var horizontal: float = cos(_orbit_pitch)
	var direction := Vector3(
		sin(_orbit_yaw) * horizontal,
		sin(_orbit_pitch),
		cos(_orbit_yaw) * horizontal
	)
	_camera.position = _orbit_target + direction * _orbit_distance
	_camera.look_at(_orbit_target, Vector3.UP)


func _capture_after_settle() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Drop a PLY: --demo-capture requires a real display/rendering driver.")
		get_tree().quit(2)
		return
	for _frame: int in range(120):
		await RenderingServer.frame_post_draw
	var destination: String = _capture_path
	if destination.begins_with("res://") or destination.begins_with("user://"):
		destination = ProjectSettings.globalize_path(destination)
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(destination)
	if error != OK:
		push_error("Drop a PLY: failed to save demo capture: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("Drop a PLY: demo capture written: ", destination)
	get_tree().quit(0)
