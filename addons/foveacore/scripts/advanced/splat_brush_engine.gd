extends Node
class_name SplatBrushEngine

## Moteur d'interaction physique et creatif avec les Gaussian Splats
## Applique des modifications de couleur / opacite par zone spherique

enum BrushMode { PAINT, ERASE, RESTORE }

@export var brush_radius: float = 0.5
@export var brush_color: Color = Color(1.0, 0.0, 0.0)
@export var brush_mode: BrushMode = BrushMode.PAINT
@export var brush_opacity: float = 1.0


func apply_brush(node: Node3D, global_hit_position: Vector3) -> bool:
    if not node is FoveaSplattable:
        return false

    var splattable := node as FoveaSplattable
    if splattable.loaded_splats.is_empty():
        return false

    var local_hit := splattable.to_local(global_hit_position)
    var modified := false

    for splat in splattable.loaded_splats:
        var splat_pos := splat.position
        if splat_pos.distance_to(local_hit) <= brush_radius:
            modified = true
            match brush_mode:
                BrushMode.PAINT:
                    splat.color = brush_color
                    splat.palette_index = -1  # Invalide le cache
                BrushMode.ERASE:
                    splat.opacity = 0.0
                BrushMode.RESTORE:
                    splat.opacity = clamp(brush_opacity, 0.0, 1.0)

    return modified
