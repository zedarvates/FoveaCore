extends ProxyFaceRenderer
class_name StarLoader

@export_file("*.json") var star_metadata_path: String = ""
@export var autoplay: bool = true
@export var playback_speed: float = 1.0

var _metadata: Dictionary = {}
var _current_frame: int = 0
var _timer: float = 0.0
var _frames_data: Array = []

func _ready():
    super._ready() # Initialize the base ProxyFaceRenderer (quad, etc.)
    
    if star_metadata_path.is_empty():
        push_warning("StarLoader: No metadata path provided.")
        return
        
    load_star_data(star_metadata_path)
    
    # Switch to the STAR shader
    if _proxy_mesh_instance and _proxy_mesh_instance.material_override:
        var shader = load("res://addons/foveacore/shaders/star_proxy.gdshader")
        if not shader:
            push_error("StarLoader: Impossible de charger le shader star_proxy.gdshader")
            return
        var mat = _proxy_mesh_instance.material_override as ShaderMaterial
        mat.shader = shader

func load_star_data(path: String):
    var abs_path = ProjectSettings.globalize_path(path)
    if not FileAccess.file_exists(abs_path):
        push_error("StarLoader: Metadata file not found: " + abs_path)
        return
        
    var file = FileAccess.open(abs_path, FileAccess.READ)
    var text = file.get_as_text()
    _metadata = JSON.parse_string(text)
    
    if _metadata.is_empty():
        push_error("StarLoader: Failed to parse metadata JSON.")
        return
        
    _frames_data = _metadata.get("frames", [])
    print("StarLoader: Loaded STAR workspace with %d frames" % _frames_data.size())
    
    apply_frame(0)

func _process(delta):
    super._process(delta) # Handle distance switching and billboarding
    
    if autoplay and _frames_data.size() > 1:
        _timer += delta * playback_speed
        var frame_duration = 1.0 / 24.0 # Assuming 24fps
        if _timer >= frame_duration:
            _timer = 0.0
            _current_frame = (_current_frame + 1) % _frames_data.size()
            apply_frame(_current_frame)

func apply_frame(idx: int):
    if idx < 0 or idx >= _frames_data.size():
        return
        
    var frame = _frames_data[idx]
    var base_dir = star_metadata_path.get_base_dir()
    
    var depth_path = base_dir + "/" + frame.get("depth_file", "")
    # In a real scenario we'd use the original image path from metadata
    # For simulation we'll use a placeholder or the same depth for albedo
    
    var depth_tex = load(depth_path)
    if depth_tex:
        if _proxy_mesh_instance.material_override is ShaderMaterial:
            var mat = _proxy_mesh_instance.material_override as ShaderMaterial
            mat.set_shader_parameter("depth_map", depth_tex)
            # Use same texture for albedo in sim mode if no albedo provided
            mat.set_shader_parameter("albedo_map", depth_tex)
            
    # Apply camera transform if present
    var pos = frame.get("camera_pos", [0,0,0])
    var rot = frame.get("camera_rot", [0,0,0])
    # Note: This is an anchoring transform. In STAR, we anchor the proxy.
    # We could update the global_position/rotation here to simulate the causal walk.
