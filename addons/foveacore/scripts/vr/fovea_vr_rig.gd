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

# Internal references
var _gaze_linker: GazeTrackerLinker = null

func _ready() -> void:
    # 1. Automatic VR Initialization (if not already handled)
    var xr_initializer: FoveaXRInitializer = get_node_or_null("FoveaXRInitializer")
    if xr_initializer == null:
        xr_initializer = FoveaXRInitializer.new()
        add_child(xr_initializer)
        
    # 2. Setup Gaze Tracker Linker
    if eye_tracking_enabled:
        _setup_gaze_tracker()
        
    # 3. Setup Controllers
    _setup_controllers()
    
    # 4. Performance: Enable viewport optimization
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
    if left_controller:
        print("FoveaVRRig: Left Hand (Tracker) detected.")
        left_controller.tracker = "left_hand"
        
    if right_controller:
        print("FoveaVRRig: Right Hand (Tracker) detected.")
        right_controller.tracker = "right_hand"

func get_hmd_transform() -> Transform3D:
    if xr_camera:
        return xr_camera.global_transform
    return global_transform

func get_hand_transform(is_right: bool) -> Transform3D:
    var controller = right_controller if is_right else left_controller
    if controller:
        return controller.global_transform
    return global_transform
