extends Node
class_name LayeredSplatGenerator

## LayeredSplatGenerator — Extracts Gaussian Splats separated by Base, Saturation, and Light
## Inspired by Digital Painting techniques (underpainting + glaze)

static func generate_layered_splats(mesh: Mesh, config: Dictionary = {}) -> Array[GaussianSplat]:
    var splats: Array[GaussianSplat] = []
    var faces = mesh.get_faces()
    var surface_count = mesh.get_surface_count()
    
    for s in range(surface_count):
        var arrays = mesh.surface_get_arrays(s)
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        var colors = arrays[Mesh.ARRAY_COLOR]
        var normals = arrays[Mesh.ARRAY_NORMAL]
        
        for i in range(vertices.size()):
            var pos = vertices[i]
            var normal = normals[i]
            var color = colors[i] if colors.size() > i else Color.WHITE
            
            # --- LAYER 1: BASE (Underpainting) ---
            # Low-density base form
            if i % 4 == 0:
                var base_splat = _create_splat(pos, normal, color, GaussianSplat.LayerType.BASE)
                base_splat.radius *= 1.5 # Larger, blurry base
                splats.append(base_splat)
            
            # --- LAYER 2: SATURATION (Artistic detail) ---
            # Extract saturation as a separate splat layer
            var sat = color.s
            if sat > 0.4:
                var sat_splat = _create_splat(pos, normal, Color(color.r, color.g, color.b, sat), GaussianSplat.LayerType.SATURATION)
                sat_splat.radius *= 0.8 # Sharper detail
                splats.append(sat_splat)
                
            # --- LAYER 3: LIGHT & SHADOW (Values) ---
            # Extract luminance for lighting/shading detail
            var val = color.v
            if val > 0.8: # Highlight
                var light_splat = _create_splat(pos, normal, Color.WHITE, GaussianSplat.LayerType.LIGHT)
                light_splat.opacity = (val - 0.8) * 5.0
                splats.append(light_splat)
            elif val < 0.2: # Shadow
                var shadow_splat = _create_splat(pos, normal, Color.BLACK, GaussianSplat.LayerType.SHADOW)
                shadow_splat.opacity = (0.2 - val) * 5.0
                splats.append(shadow_splat)
                
    return splats

static func _create_splat(pos: Vector3, norm: Vector3, col: Color, type: GaussianSplat.LayerType) -> GaussianSplat:
    var splat = GaussianSplat.new()
    splat.position = pos
    splat.normal = norm
    splat.surface_normal = norm # Store origin surface normal
    splat.color = col
    splat.layer_type = type
    splat.radius = 0.05
    return splat
