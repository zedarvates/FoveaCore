extends Node3D

## Validation visuelle du rendu triangle vs quad
## Permet de comparer côte à côte les deux méthodes

@export var test_mode: String = "triangle"  # "triangle" ou "quad" ou "both"
@export var splat_count: int = 500

var triangle_renderer: FoveaSplatRenderer
var quad_renderer: FoveaSplatRenderer

func _ready() -> void:
    print("\n========== Validation Visuelle ==========")
    print("Mode: %s" % test_mode)
    print("Nombre de splats: %d" % splat_count)
    print("========================================\n")
    
    if test_mode == "both":
        _setup_side_by_side()
    elif test_mode == "triangle":
        _setup_triangle_only()
    else:
        _setup_quad_only()

func _setup_triangle_only() -> void:
    triangle_renderer = FoveaSplatRenderer.new()
    triangle_renderer.use_triangle_mesh = true
    triangle_renderer.splat_subdivisions = 16
    triangle_renderer.name = "TriangleRenderer"
    add_child(triangle_renderer)
    
    # Positionner
    triangle_renderer.global_position = Vector3(0, 0, 0)
    
    print("✓ Triangle mesh activé (16 subdivisions)")
    print("  - Pas de discard() par fragment")
    print("  - Pas de exp() par fragment")
    print("  - Géométrie exacte de l'ellipse")

func _setup_quad_only() -> void:
    quad_renderer = FoveaSplatRenderer.new()
    quad_renderer.use_triangle_mesh = false
    quad_renderer.name = "QuadRenderer"
    add_child(quad_renderer)
    
    quad_renderer.global_position = Vector3(0, 0, 0)
    
    print("✓ Quad mesh activé (méthode classique)")
    print("  - Utilise discard() pour masquer pixels hors ellipse")
    print("  - Utilise exp() pour falloff gaussien")
    print("  - Overdraw élevé")

func _setup_side_by_side() -> void:
    # Triangle à gauche
    triangle_renderer = FoveaSplatRenderer.new()
    triangle_renderer.use_triangle_mesh = true
    triangle_renderer.splat_subdivisions = 16
    triangle_renderer.name = "TriangleRenderer"
    add_child(triangle_renderer)
    triangle_renderer.global_position = Vector3(-3, 0, 0)
    
    # Quad à droite
    quad_renderer = FoveaSplatRenderer.new()
    quad_renderer.use_triangle_mesh = false
    quad_renderer.name = "QuadRenderer"
    add_child(quad_renderer)
    quad_renderer.global_position = Vector3(3, 0, 0)
    
    print("✓ Comparaison côte à côte")
    print("  GAUCHE: Triangle mesh (optimisé)")
    print("  DROITE: Quad mesh (classique)")
    print("\nPoints à vérifier:")
    print("  1. Qualité visuelle similaire")
    print("  2. Pas d'artefacts géométriques")
    print("  3. Transition douce des bords")
    print("  4. Couleurs/opacité correctes")

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        get_tree().quit()