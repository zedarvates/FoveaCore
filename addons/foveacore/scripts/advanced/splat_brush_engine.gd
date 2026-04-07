@tool
extends Node3D
class_name SplatBrushEngine

## SplatBrushEngine — Dynamic editing of Gaussian Splats and Point Clouds
## Supports Erase, Recolor, and Density adjustments in the viewport

enum BrushMode { ERASE, RECOLOR, DENSITY, SMOOTH }

@export var current_mode: BrushMode = BrushMode.ERASE
@export var brush_radius: float = 0.5
@export var brush_strength: float = 1.0
@export var paint_color: Color = Color.WHITE

## Apply brush operation to a list of Gaussian Splats
func apply_brush(splats: Array[GaussianSplat], brush_pos: Vector3) -> Array[GaussianSplat]:
    var modified_splats: Array[GaussianSplat] = []
    
    for splat in splats:
        var distance = splat.position.distance_to(brush_pos)
        
        if distance <= brush_radius:
            match current_mode:
                BrushMode.ERASE:
                    # Mark for deletion by reducing opacity to 0
                    splat.opacity = lerp(splat.opacity, 0.0, brush_strength)
                BrushMode.RECOLOR:
                    splat.color = splat.color.lerp(paint_color, brush_strength)
                BrushMode.DENSITY:
                    # Adjust radius based on density painting
                    splat.radius = splat.radius * (1.0 + brush_strength * 0.1)
                BrushMode.SMOOTH:
                    # Placeholder for smoothing normal/covariance
                    pass
        
        # Only keep splats with visible opacity
        if splat.opacity > 0.01:
            modified_splats.append(splat)
            
    return modified_splats

## Automated Denoising: Remove isolated points
func auto_denoise(splats: Array[GaussianSplat], neighbor_threshold: float = 0.5, min_neighbors: int = 3) -> Array[GaussianSplat]:
    var cleaned: Array[GaussianSplat] = []
    # Simplified spatial hashing or distance check (O(n^2) slowed down version for GDScript)
    # Ideally should be done in GDExtension with Octree
    for i in range(splats.size()):
        var neighbors = 0
        for j in range(max(0, i-50), min(splats.size(), i+50)): # Local check
            if splats[i].position.distance_to(splats[j].position) < neighbor_threshold:
                neighbors += 1
        
        if neighbors >= min_neighbors:
            cleaned.append(splats[i])
            
    return cleaned
