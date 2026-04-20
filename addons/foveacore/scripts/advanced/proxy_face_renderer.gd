# ============================================================================
# FoveaEngine : proxy_face_renderer.gd
# LOD Dynamique : Remplace des millions de Splats par un Fake Volume 2D
# ============================================================================

extends Node3D
class_name ProxyFaceRenderer

@export var target_splattable: Node3D # Le FoveaSplattable (MultiMesh) à remplacer
@export var switch_distance: float = 30.0 # Distance d'activation en mètres
@export var proxy_material: ShaderMaterial # Matériau utilisant fake_volume.gdshader
@export var proxy_scale: Vector2 = Vector2(1.0, 1.0)

var _proxy_mesh_instance: MeshInstance3D
var _camera: Camera3D

func _ready():
    # 1. Création dynamique du Quad (Seulement 2 triangles !)
    _proxy_mesh_instance = MeshInstance3D.new()
    var quad = QuadMesh.new()
    quad.size = proxy_scale
    _proxy_mesh_instance.mesh = quad
    
    if proxy_material:
        _proxy_mesh_instance.material_override = proxy_material
        
    add_child(_proxy_mesh_instance)
    _proxy_mesh_instance.hide() # Caché par défaut si on est près

func _process(_delta):
    # 2. Recherche robuste de la caméra active (Correction Tâche #44)
    # Compatible avec le mode Desktop ET les casques VR (XRCamera3D)
    if not _camera or not is_instance_valid(_camera):
        var viewport = get_viewport()
        if viewport:
            _camera = viewport.get_camera_3d()
            
    if not _camera or not target_splattable:
        return
        
    # 3. Calcul de la distance
    var dist = global_position.distance_to(_camera.global_position)
    
    # 4. Bascule (Switch) de LOD
    if dist > switch_distance:
        # Trop loin : On affiche le Proxy (1 Quad) et on coupe le rendu lourd
        if not _proxy_mesh_instance.visible:
            _proxy_mesh_instance.show()
            if "visible" in target_splattable:
                target_splattable.visible = false
                
    else:
        # Assez près : On affiche les Splats en haute qualité (Fovéation dynamique)
        if _proxy_mesh_instance.visible:
            _proxy_mesh_instance.hide()
            if "visible" in target_splattable:
                target_splattable.visible = true