extends Node
class_name GazeTrackerLinker

## GazeTrackerLinker — Connects the OpenXR Eye Tracker to the foveated renderer
## Depends on Godot OpenXR Eye Tracking plugin or extension

signal eye_updated(gaze: Vector3, eye: int) # eye: 0 for Left, 1 for Right, 2 for Combined
signal focus_detected(point: Vector3)

@export var eye_tracking_enabled := true
@export var manager: Node = null # FoveaCoreManager
@export var debug_visualization := false

# Reference to the XRInterface
var _xr_interface: XRInterface = null
var _last_gaze_point: Vector3 = Vector3.ZERO

func _ready() -> void:
	_xr_interface = XRServer.find_interface("OpenXR")
	if manager == null:
		manager = get_node_or_null("/root/FoveaCoreManager")
		
	print("GazeTrackerLinker: Attempting to bind to OpenXR interface...")

func _process(_delta: float) -> void:
	if eye_tracking_enabled and _xr_interface:
		_update_eye_data()

func _update_eye_data() -> void:
	# OpenXR Eye Tracking standard:
	# 1. Fetch eye pose from XR Server
	# 2. Project gaze vector onto the far plane or detected scene objects
	# 3. Feed gaze point (eye centered) to Foveated Controller
	
	# Placeholder for actual OpenXR API call (e.g., via GDExtension or Plugin)
	var gaze_vec = _fetch_openxr_gaze()
	if gaze_vec != Vector3.ZERO:
		_last_gaze_point = _calculate_gaze_world_hit(gaze_vec)
		
		# Link to the foveated renderer in FoveaCoreManager
		if manager and manager._foveated_controller:
			manager._foveated_controller.update_gaze(_last_gaze_point, gaze_vec)
			eye_updated.emit(gaze_vec, 2) # Combined gaze
			focus_detected.emit(_last_gaze_point)

func _calculate_gaze_world_hit(gaze_vec: Vector3) -> Vector3:
	# Raycast or projection logic to find the 3D focus point
	return get_viewport().get_camera_3d().global_transform.origin + (gaze_vec * 100.0)

func _fetch_openxr_gaze() -> Vector3:
	# OpenXR Eye Gaze logic for Godot 4.3+
	# 1. Try to find the gaze tracker
	var tracker_name: String = "eye_gaze"
	var tracker: XRPositionalTracker = XRServer.get_tracker(tracker_name)
	
	if tracker and tracker.has_pose("default"):
		var pose: XRPose = tracker.get_pose("default")
		# The direction is typically Vector3.FORWARD transformed by the pose
		var gaze_dir: Vector3 = pose.transform.basis.z * -1.0 # Forward in XR
		return gaze_dir
		
	# Fallback: Forward vector relative to camera (not tracking, just center)
	return Vector3.ZERO
