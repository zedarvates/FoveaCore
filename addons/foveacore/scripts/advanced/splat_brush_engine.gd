# ============================================================================
# FoveaEngine : splat_brush_engine.gd
# Moteur d'interaction physique et créative avec les Gaussian Splats
# ============================================================================

extends Node
class_name SplatBrushEngine

enum BrushMode { PAINT, ERASE, RESTORE }

@export var brush_radius: float = 0.5
@export var brush_color: Color = Color(1.0, 0.0, 0.0)
@export var brush_mode: BrushMode = BrushMode.PAINT
@export var brush_opacity: float = 1.0

## Applique un coup de pinceau sphérique sur un noeud FoveaSplattable
## hit_position doit être en coordonnées globales (ex: intersection d'un RayCast VR)
func apply_brush(splattable: Node3D, global_hit_position: Vector3) -> bool:
    if not splattable.has_method("get_multimesh"):
        return false
        
    var multimesh: MultiMesh = splattable.get_multimesh()
    if not multimesh or multimesh.buffer.is_empty():
        return false
        
    # Convertir la position d'impact globale en position locale de l'objet
    var local_hit = splattable.to_local(global_hit_position)
    
    var buffer = multimesh.buffer
    var splat_count = multimesh.instance_count
    var aabb_min = splattable.custom_aabb.position
    var aabb_max = splattable.custom_aabb.end
    var range_xyz = aabb_max - aabb_min
    
    var modified = false
    
    # Parcours des splats (Optimisation future : Octree ou Compute Shader pour la VR)
    for i in range(splat_count):
        var offset = i * 16 # Notre structure Rust fait exactement 16 octets
        
        # 1. Décodage de la position (Spatial Quantization)
        var qx = buffer.decode_u16(offset)
        var qy = buffer.decode_u16(offset + 2)
        var qz = buffer.decode_u16(offset + 4)
        
        var px = aabb_min.x + (float(qx) / 65535.0) * range_xyz.x
        var py = aabb_min.y + (float(qy) / 65535.0) * range_xyz.y
        var pz = aabb_min.z + (float(qz) / 65535.0) * range_xyz.z
        var pos = Vector3(px, py, pz)
        
        # 2. Test de collision sphérique avec le pinceau
        if pos.distance_to(local_hit) <= brush_radius:
            modified = true
            
            match brush_mode:
                BrushMode.PAINT:
                    # Encodage de la couleur en RGB565
                    var r = int(clamp(brush_color.r, 0.0, 1.0) * 31.0)
                    var g = int(clamp(brush_color.g, 0.0, 1.0) * 63.0)
                    var b = int(clamp(brush_color.b, 0.0, 1.0) * 31.0)
                    var rgb565 = (r << 11) | (g << 5) | b
                    buffer.encode_u16(offset + 8, rgb565)
                    
                BrushMode.ERASE:
                    # Mettre l'opacité (Byte 12) à 0 désactive virtuellement le splat
                    buffer.encode_u8(offset + 12, 0)
                    
                BrushMode.RESTORE:
                    # Restaure l'opacité complète
                    var op8 = int(clamp(brush_opacity, 0.0, 1.0) * 255.0)
                    buffer.encode_u8(offset + 12, op8)

    if modified:
        # Forcer Godot à uploader le buffer modifié vers la VRAM
        multimesh.buffer = buffer
        return true
        
    return false