extends Node
class_name TexturedSplatGenerator

## TexturedSplatGenerator — Advanced textured stamping (Sponge, Brushes)
## Replaces simple Gaussians with complex alpha masks for better material feel

## Generate splats with textured brush types based on surface roughness
static func generate_textured_splats(mesh: Mesh) -> Array[GaussianSplat]:
    var splats: Array[GaussianSplat] = []
    
    var arrays = mesh.surface_get_arrays(0)
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var normals = arrays[Mesh.ARRAY_NORMAL]
    var colors = arrays[Mesh.ARRAY_COLOR]
    
    for i in range(vertices.size()):
        if i % 4 != 0: continue # Density reduction for textured splats
        
        var pos = vertices[i]
        var norm = normals[i]
        var col = colors[i] if colors.size() > i else Color.WHITE
        
        var splat = GaussianSplat.new()
        splat.position = pos
        splat.normal = norm
        splat.color = col
        splat.radius = 0.08
        
        # LOGIQUE DE SÉLECTION DU PINCEAU:
        # On analyse la normale locale pour détecter la "rugosité"
        var roughness = _calculate_local_roughness(i, normals)
        
        if roughness > 0.5:
            splat.brush_type = GaussianSplat.BrushType.STONE
        elif roughness > 0.3:
            splat.brush_type = GaussianSplat.BrushType.SPONGE
        else:
            splat.brush_type = GaussianSplat.BrushType.GAUSSIAN
            
        splats.append(splat)
        
    return splats

static func _calculate_local_roughness(idx: int, normals: PackedVector3Array) -> float:
    # Simuler un calcul de variance des normales
    var n1 = normals[idx]
    var n2 = normals[idx-1] if idx > 0 else n1
    return n1.distance_to(n2)
