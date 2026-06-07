extends XROrigin3D
class_name FoveaVRRig

## FoveaVRRig — The standard XR Origin structure for FoveaEngine
## Incorporates eye-tracking support, controller interactions and head tracking.

@export_group("Components")
@export var xr_camera: XRCamera3D = null
@export var left_controller: XRController3D = null
@export var right_controller: XRController3D = null

@export_group("Features")
@export var eye_tracking_enabled := true
@export var hand_tracking_fallback := true
@export var brush_enabled := false

# Internal references
var _gaze_linker: GazeTrackerLinker = null

func _ready() -> void:
	# 0. Fallback detection of components if not set in inspector
	if xr_camera == null:
		xr_camera = get_node_or_null("XRCamera3D")
	if left_controller == null:
		left_controller = get_node_or_null("LeftHand")
	if right_controller == null:
		right_controller = get_node_or_null("RightHand")

	# 1. Automatic VR Initialization (if not already handled)
	var xr_initializer: FoveaXRInitializer = get_node_or_null("FoveaXRInitializer")
	if xr_initializer == null:
		xr_initializer = FoveaXRInitializer.new()
		add_child(xr_initializer)
		
	xr_initializer.xr_failed.connect(_on_xr_failed)

	# 2. Setup Gaze Tracker Linker
	if eye_tracking_enabled:
		_setup_gaze_tracker()
		
	# 3. Setup Controllers
	_setup_controllers()

	# 4. Setup VR Brush
	if brush_enabled:
		_setup_vr_brush()
	
	# 5. Performance: Enable viewport optimization
	# In Godot 4.3+, MSAA and HDR are crucial for VR.
	# get_viewport().msaa_3d = Viewport.MSAA_4X
	# get_viewport().use_debanding = true
	# get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED # FXAA is usually bad in VR
	
	print("FoveaVRRig: Rig assembled and ready.")

func _setup_gaze_tracker() -> void:
	_gaze_linker = GazeTrackerLinker.new()
	_gaze_linker.eye_tracking_enabled = true
	add_child(_gaze_linker)
	print("FoveaVRRig: GazeTrackerLinker integrated.")

func _setup_controllers() -> void:
	var left = left_controller if left_controller else get_node_or_null("LeftHand")
	if left:
		print("FoveaVRRig: Left Hand (Tracker) detected.")
		left.tracker = "left_hand"
		
	var right = right_controller if right_controller else get_node_or_null("RightHand")
	if right:
		print("FoveaVRRig: Right Hand (Tracker) detected.")
		right.tracker = "right_hand"

func _setup_vr_brush() -> void:
	var controller = right_controller if right_controller else get_node_or_null("RightHand")
	if controller:
		var brush = preload("res://addons/foveacore/scripts/advanced/splat_vr_brush.gd").new()
		brush.name = "SplatVRBrush"
		controller.add_child(brush)
		print("FoveaVRRig: SplatVRBrush integrated on right controller.")
	else:
		push_warning("FoveaVRRig: Right controller not found, cannot attach SplatVRBrush.")

func _on_xr_failed(reason: String) -> void:
	print("FoveaVRRig: OpenXR failed (%s). Activating Desktop Orbit Camera Fallback." % reason)
	_activate_desktop_fallback()

func _activate_desktop_fallback() -> void:
	if xr_camera:
		if not xr_camera.has_node("FoveaOrbitCamera"):
			var orbit_cam = FoveaOrbitCamera.new()
			orbit_cam.name = "FoveaOrbitCamera"
			xr_camera.add_child(orbit_cam)
			print("FoveaVRRig: Orbit camera fallback attached to ", xr_camera.name)

func get_hmd_transform() -> Transform3D:
	if xr_camera:
		return xr_camera.global_transform
	return global_transform

func get_hand_transform(is_right: bool) -> Transform3D:
	var controller = right_controller if is_right else left_controller
	if controller:
		return controller.global_transform
	return global_transform
