extends Node
class_name FoveaXRInitializer

## FoveaXRInitializer — Handles proper OpenXR 1.0+ startup and configuration
## 
## Following OpenXR 1.0 standards for Godot 4.3+ (Mobile / Desktop)

signal xr_started
signal xr_failed(reason: String)

@export var auto_initialize := true
@export var passthrough_enabled := false
@export var foveation_level := 2 # 0: None, 1: Low, 2: Med, 3: High
@export var prefer_vulkan_mobile := true

var xr_interface: XRInterface = null
var xr_is_initialized := false

func _ready() -> void:
    if auto_initialize:
        # Delay initialization slightly to ensure all nodes are ready
        get_tree().create_timer(0.1).timeout.connect(initialize_xr)

func initialize_xr() -> void:
    print("FoveaEngine: Initializing XR Architecture...")
    
    # 1. Find OpenXR Interface
    xr_interface = XRServer.find_interface("OpenXR")
    
    if not xr_interface:
        var err_msg = "OpenXR Interface not found. Ensure the plugin is enabled and supported."
        push_error(err_msg)
        xr_failed.emit(err_msg)
        return
        
    # 2. Check if the interface is available and can be initialized
    if xr_interface.is_initialized():
        print("OpenXR is already successfully initialized.")
        _setup_viewport()
        return
        
    # 3. Request initialization
    if xr_interface.initialize():
        print("OpenXR: Interface initialized successfully.")
        
        # 4. Configure Viewport
        _setup_viewport()
        
        # 5. Connect to signals for runtime state
        xr_interface.session_begun.connect(_on_session_begun)
        xr_interface.session_stopping.connect(_on_session_stopping)
        
        # 6. Apply Foveation (OpenXR Extension)
        _apply_foveation_settings()
        
        # 7. Passthrough (if requested)
        if passthrough_enabled:
            _enable_passthrough()
            
        xr_is_initialized = true
        xr_started.emit()
    else:
        var err_msg = "OpenXR: Failed to initialize. Check if your HMD is connected and OpenXR runtime is set correctly."
        push_error(err_msg)
        xr_failed.emit(err_msg)

func _setup_viewport() -> void:
    var viewport := get_viewport()
    viewport.use_xr = true
    
    # Performance optimizations for VR
    # Godot 4.x specific:
    ProjectSettings.set_setting("rendering/driver/threads/thread_model", 2) # Multi-threaded
    
    # Set Refresh Rate (if possible)
    if xr_interface.has_refresh_rate(90.0):
        xr_interface.set_refresh_rate(90.0)
        print("OpenXR: Refresh rate set to 90Hz.")
    elif xr_interface.has_refresh_rate(72.0):
        xr_interface.set_refresh_rate(72.0)
        print("OpenXR: Refresh rate set to 72Hz.")

func _apply_foveation_settings() -> void:
    # OpenXR Fixed Foveated Rendering (if supported by hardware/driver)
    if xr_interface.get("vrs_mode") != null:
        xr_interface.vrs_mode = foveation_level
        print("OpenXR: VRS Foveation set to level ", foveation_level)

func _enable_passthrough() -> void:
    if xr_interface.is_passthrough_supported():
        if xr_interface.start_passthrough():
            get_viewport().transparent_bg = true
            print("OpenXR: Passthrough started.")
        else:
            print("OpenXR: Failed to start passthrough.")
    else:
        print("OpenXR: Passthrough NOT supported on this device.")

func _on_session_begun() -> void:
    print("OpenXR: Session Begun - HMD is active.")

func _on_session_stopping() -> void:
    print("OpenXR: Session Stopping - User exited VR.")
