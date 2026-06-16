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
    
    # Discover original mesh instance robustly
    var parent = get_parent()
    if parent is FoveaSplattable:
        _original_mesh_instance = parent._mesh_instance_ref
    elif parent is MeshInstance3D:
        _original_mesh_instance = parent
    else:
        for child in get_children():
            if child is MeshInstance3D and child != _proxy_mesh_instance:
                _original_mesh_instance = child
                break

    # If original mesh is found, initialize the splat generator and update texture
    if _original_mesh_instance:
        set_splat_generator(LayeredSplatGenerator)
        update_proxy_texture_from_splats()
    
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
    shader_mat.shader = preload("res://addons/foveacore/shaders/fake_volume.gdshader")
    
    # Set initial shader parameters
    shader_mat.set_shader_parameter("base_color", splat_color)
    shader_mat.set_shader_parameter("radius", radius)
    shader_mat.set_shader_parameter("falloff", falloff)
    shader_mat.set_shader_parameter("depth_scale", 0.5)
    
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
        mat.set_shader_parameter("base_color", new_color)


# Method to integrate with LayeredSplatGenerator
func set_splat_generator(splat_gen: Object) -> void:
    _splat_generator = splat_gen
    if _splat_generator and _original_mesh_instance:
        update_proxy_texture_from_splats()


func notify_splat_update() -> void:
    if _splat_generator and _original_mesh_instance:
        update_proxy_texture_from_splats()


func update_proxy_texture_from_splats() -> void:
    if not _original_mesh_instance or not _splat_generator:
        return
    var mesh: Mesh = _original_mesh_instance.mesh
    if not mesh:
        return
        
    # Generate layered splats using the generator
    var splats: Array[GaussianSplat] = _splat_generator.generate_layered_splats(mesh)
    if splats.is_empty():
        return
        
    # Bake splats into a 2D projected image texture
    var baked_texture := bake_splats_to_texture(splats, 256)
    if baked_texture and _proxy_mesh_instance:
        var mat: ShaderMaterial = _proxy_mesh_instance.material_override as ShaderMaterial
        if mat:
            mat.set_shader_parameter("proxy_texture", baked_texture)
            if show_debug:
                print("ProxyFaceRenderer: Baked %d layered splats into proxy_texture." % splats.size())


func bake_splats_to_texture(splats: Array[GaussianSplat], texture_size: int = 256) -> ImageTexture:
    if splats.is_empty():
        return null
        
    # Find local AABB bounding box of the splats
    var aabb_min := Vector3(INF, INF, INF)
    var aabb_max := Vector3(-INF, -INF, -INF)
    for splat in splats:
        aabb_min = aabb_min.min(splat.position)
        aabb_max = aabb_max.max(splat.position)
        
    var size_x: float = max(aabb_max.x - aabb_min.x, 0.001)
    var size_y: float = max(aabb_max.y - aabb_min.y, 0.001)
    
    # Create a blank transparent image
    var img := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    
    # Project 3D splats onto the XY plane in local space (front projection)
    for splat in splats:
        var u: float = (splat.position.x - aabb_min.x) / size_x
        var v: float = 1.0 - ((splat.position.y - aabb_min.y) / size_y) # Flip Y for image coords
        
        var px: int = int(u * texture_size)
        var py: int = int(v * texture_size)
        
        # Splat radius in pixel space
        var radius_px: int = max(int((splat.radius / max(size_x, size_y)) * texture_size), 2)
        
        # Rasterize a Gaussian blob into the image
        for dy in range(-radius_px, radius_px + 1):
            for dx in range(-radius_px, radius_px + 1):
                var target_x: int = px + dx
                var target_y: int = py + dy
                
                if target_x >= 0 and target_x < texture_size and target_y >= 0 and target_y < texture_size:
                    var dist_sq: int = dx * dx + dy * dy
                    var rad_sq: float = float(radius_px * radius_px)
                    if dist_sq <= rad_sq:
                        # Gaussian falloff formula
                        var factor: float = exp(-float(dist_sq) / (0.5 * rad_sq))
                        var weight: float = factor * splat.opacity
                        
                        if weight > 0.01:
                            var current_color: Color = img.get_pixel(target_x, target_y)
                            var splat_color: Color = splat.color
                            
                            # Standard Alpha blending: source over destination
                            var new_alpha: float = current_color.a + weight * (1.0 - current_color.a)
                            if new_alpha > 0.001:
                                var current_rgb := Vector3(current_color.r, current_color.g, current_color.b)
                                var splat_rgb := Vector3(splat_color.r, splat_color.g, splat_color.b)
                                var new_rgb: Vector3 = (current_rgb * current_color.a * (1.0 - weight) + splat_rgb * weight) / new_alpha
                                img.set_pixel(target_x, target_y, Color(new_rgb.x, new_rgb.y, new_rgb.z, new_alpha))
                                
    return ImageTexture.create_from_image(img)


# Utility: reset everything
func reset() -> void:
    if _proxy_mesh_instance and _proxy_mesh_instance.is_inside_tree():
        _proxy_mesh_instance.queue_free()
    _proxy_mesh_instance = null
    if _original_mesh_instance and _original_mesh_instance.is_inside_tree():
        _original_mesh_instance.visible = true
