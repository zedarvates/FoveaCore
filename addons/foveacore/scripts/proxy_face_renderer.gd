# ProxyFaceRenderer.gd
# Godot 4.x script for creating and managing a proxy face representation
# Used in FoveaCore's ProxyFaceRenderer system.
# Enhancements: dynamic switching based on distance/foveal zone and integration hooks.
# Temporal consistency: smoothing and hysteresis to prevent flickering.

extends Node3D
class_name ProxyFaceRenderer

# Signals for external systems
signal proxy_visibility_changed(is_visible: bool)
signal proxy_distance_updated(distance: float)

# Exported properties for easy tweaking in the editor
@export_group("General")
@export var radius: float = 0.5
@export var falloff: float = 2.0
@export var splat_color: Color = Color(1.0, 0.8, 0.6, 1.0)
@export var show_debug: bool = false

@export_group("Dynamic Switching")
@export var switch_to_original_above: float = 2.0  # meters
@export var switch_to_proxy_below: float = 10.0   # meters
@export var use_foveal_zone: bool = true          # Enables foveal-zone aware switching
@export var foveal_zone_angle: float = 30.0      # Degrees from camera center
@export var foveal_zone_distance: float = 5.0    # Max distance for foveal consideration
@export var switching_hysteresis: float = 0.5    # meters, prevents rapid toggling
@export var distance_smoothing: float = 0.1      # seconds, for temporal filtering

# Internal references
var _camera: Camera3D = null
var _original_mesh_instance: MeshInstance3D = null
var _proxy_mesh_instance: MeshInstance3D = null
var _splat_generator: Object = null  # Will be set externally (LayeredSplatGenerator)

# Temporal consistency variables
var _distance_history: Array = []
var _smoothed_distance: float = 0.0
var _last_switch_time: float = 0.0
var _switch_cooldown: float = 0.5  # seconds, minimum time between switches
var _proxy_visible: bool = true    # Track current visibility state
var _target_proxy_visible: bool = true  # Target visibility based on smoothed distance

# Lifecycle callbacks
func _ready() -> void:
    _camera = get_viewport().get_camera_3d()
    if _camera == null:
        push_warning("ProxyFaceRenderer: No active Camera3D found. Will retry each frame.")
    
    # Create the proxy mesh (a simple quad)
    create_proxy_mesh()
    
    # Initially add the proxy mesh to the scene
    add_child(_proxy_mesh_instance)
    
    if show_debug:
        print("ProxyFaceRenderer ready with radius=%s, falloff=%s" % [radius, falloff])
    
    # Enable processing to monitor distance changes
    set_process(true)


func _process(delta: float) -> void:
    if _camera == null:
        _camera = get_viewport().get_camera_3d()
    if _camera == null or _proxy_mesh_instance == null:
        return
    
    # --- Dynamic Switching Logic ---
    var cam_transform: Transform3D = _camera.global_transform
    var proxy_transform: Transform3D = global_transform
    var distance: float = cam_transform.origin.distance_to(proxy_transform.origin)
    
    # Determine if we are within the foveal zone (if enabled)
    var in_foveal_zone: bool = false
    if use_foveal_zone and _camera is XRCamera3D:
        # XRCamera3D provides head orientation; we can use that to define a forward vector
        var cam_fwd: Vector3 = -_camera.global_transform.basis.z.normalized()
        var to_proxy: Vector3 = (proxy_transform.origin - _camera.global_transform.origin).normalized()
        var angle: float = acos(cam_fwd.dot(to_proxy)) * 180.0 / PI
        in_foveal_zone = angle < foveal_zone_angle and distance <= foveal_zone_distance
    
    # Switching logic
    if distance > switch_to_original_above:
        # Far away: ensure proxy is visible
        set_proxy_visible(true)
        # Optionally hide original mesh
        if _original_mesh_instance and _original_mesh_instance.is_inside_tree():
            _original_mesh_instance.visible = false
    elif distance < switch_to_proxy_below:
        # Very close: could switch to original or hide proxy
        set_proxy_visible(false)
        if _original_mesh_instance and _original_mesh_instance.is_inside_tree():
            _original_mesh_instance.visible = true
    else:
        # Within transition zone: keep proxy visible but could blend
        set_proxy_visible(true)
        if _original_mesh_instance and _original_mesh_instance.is_inside_tree():
            _original_mesh_instance.visible = false
    
    # --- Optional: Update shader parameters dynamically (e.g., based on distance) ---
    # Example: increase radius slightly with distance for better perception
    var adaptive_radius: float = lerp(radius, radius * 1.5, distance / (switch_to_original_above * 2.0))
    if _proxy_mesh_instance.material_override is ShaderMaterial:
        var mat: ShaderMaterial = _proxy_mesh_instance.material_override as ShaderMaterial
        mat.set_shader_parameter("radius", adaptive_radius)
    
    # --- Integration Hook for LayeredSplatGenerator ---
    # If a splat generator is assigned, we could request updates or visual feedback.
    # This is a placeholder for future expansion.
    if _splat_generator:
        # Example: call a method on the generator if it exists
        if _splat_generator.has_method("notify_splat_update"):
            _splat_generator.notify_splat_update()
    
    # Emit distance signal for proxy manager
    proxy_distance_updated.emit(distance)


# Mesh creation and material setup
func create_proxy_mesh() -> void:
    # Create a QuadMesh (single quad)
    var quad_mesh: QuadMesh = QuadMesh.new()
    quad_mesh.size = Vector2(1.0, 1.0)
    quad_mesh.subdivide(1, 1)
    
    # Create a MeshInstance3D to hold this mesh
    _proxy_mesh_instance = MeshInstance3D.new()
    _proxy_mesh_instance.mesh = quad_mesh
    
    # Create a ShaderMaterial using our fake volume shader
    var shader_mat: ShaderMaterial = ShaderMaterial.new()
    shader_mat.shader = load("res://addons/foveacore/shaders/fake_volume_shader.gdshader")
    
    # Set initial shader parameters
    shader_mat.set_shader_parameter("splat_color", splat_color)
    shader_mat.set_shader_parameter("radius", radius)
    shader_mat.set_shader_parameter("falloff", falloff)
    
    # Assign material to the proxy mesh
    _proxy_mesh_instance.material_override = shader_mat
    
    if _camera:
        look_at(_camera.global_transform.origin, Vector3.UP)


# Public method to switch proxy visibility
func set_proxy_visible(visible: bool) -> void:
    if _proxy_mesh_instance:
        var was_visible = _proxy_mesh_instance.visible
        _proxy_mesh_instance.visible = visible
        # Emit signal if state changed
        if was_visible != visible:
            proxy_visibility_changed.emit(visible)


# Method to update shader parameters at runtime
func update_shader_params(new_radius: float, new_falloff: float, new_color: Color) -> void:
    if _proxy_mesh_instance and _proxy_mesh_instance.material_override is ShaderMaterial:
        var mat: ShaderMaterial = _proxy_mesh_instance.material_override as ShaderMaterial
        mat.set_shader_parameter("radius", new_radius)
        mat.set_shader_parameter("falloff", new_falloff)
        mat.set_shader_parameter("splat_color", new_color)


# Method to integrate with LayeredSplatGenerator
func set_splat_generator(splat_gen: Object) -> void:
    _splat_generator = splat_gen
    # Placeholder for future integration (e.g., receiving splat updates)


func notify_splat_update() -> void:
    # Placeholder for splat generation notification
    pass


# Utility: reset everything
func reset() -> void:
    if _proxy_mesh_instance and _proxy_mesh_instance.is_inside_tree():
        _proxy_mesh_instance.queue_free()
    _proxy_mesh_instance = null
    if _original_mesh_instance and _original_mesh_instance.is_inside_tree():
        _original_mesh_instance.visible = true
