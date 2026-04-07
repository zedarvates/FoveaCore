extends Node
class_name HierarchicalSplatGenerator

## HierarchicalSplatGenerator — Optimized splatting with Variable Sizes
## Large splats for base color, tiny splats for high-detail areas

## Generate splats by analyzing color variance across the mesh
static func generate_hierarchical_splats(mesh: Mesh, detail_threshold: float = 0.1) -> Array[GaussianSplat]:
    var splats: Array[GaussianSplat] = []
    # Simplified approach: We sample the mesh at multiple frequencies
    # Layer 1: Base (Large Splats)
    # Layer 2: Detail (Small Splats only where color changes rapidly)
    
    var arrays = mesh.surface_get_arrays(0)
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var colors = arrays[Mesh.ARRAY_COLOR]
    var normals = arrays[Mesh.ARRAY_NORMAL]
    
    # Track which areas have already been 'detailed'
    var detail_mask: Array[bool] = []
    detail_mask.resize(vertices.size())
    detail_mask.fill(false)
    
    # 1. PASSE 1: Détection des zones de détail (Haute fréquence)
    for i in range(vertices.size()):
        var color = colors[i] if colors.size() > i else Color.WHITE
        var neighbors = _get_neighbor_indices(i, vertices)
        
        for n_idx in neighbors:
            var n_color = colors[n_idx]
            if color.distance_to(n_color) > detail_threshold:
                detail_mask[i] = true
                break
                
    # 2. PASSE 2: Génération Hiérarchique
    for i in range(vertices.size()):
        var pos = vertices[i]
        var norm = normals[i]
        var col = colors[i] if colors.size() > i else Color.WHITE
        
        if detail_mask[i]:
            # ZONE DE DÉTAIL: Petits splats denses
            for j in range(3): # Sub-sampling for extra detail
                var splat = _create_splat(pos + _rand_vec(0.02), norm, col, 0.03)
                splats.append(splat)
        else:
            # ZONE UNIFORME: Grands splats rares
            if i % 8 == 0: # Réduction de densité x8
                var splat = _create_splat(pos, norm, col, 0.15) # Splat de grande dimension
                splats.append(splat)
                
    return splats

static func _create_splat(pos: Vector3, norm: Vector3, col: Color, radius: float) -> GaussianSplat:
    var splat = GaussianSplat.new()
    splat.position = pos
    splat.normal = norm
    splat.surface_normal = norm
    splat.color = col
    splat.radius = radius
    splat.opacity = 1.0
    return splat

static func _get_neighbor_indices(idx: int, vertices: PackedVector3Array) -> Array[int]:
    # Simplified neighbor lookup for the prototype
    var neighbors: Array[int] = []
    if idx > 0: neighbors.append(idx-1)
    if idx < vertices.size()-1: neighbors.append(idx+1)
    return neighbors

static func _rand_vec(spread: float) -> Vector3:
    return Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))
