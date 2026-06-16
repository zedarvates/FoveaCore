extends Node3D
class_name SplatVRBrush

## SplatVRBrush — Pinceau VR interactif pour modifier les splats en 3D.
## S'attache à un XRController3D pour manipuler la couleur, l'opacité et l'advection.

@export var brush_engine: SplatBrushEngine = null
@export var controller: XRController3D = null
@export var interaction_radius := 0.3
@export var haptic_action := "haptic"
@export var paint_button := "trigger_click"

# Indicateur visuel de la taille et couleur du pinceau dans l'espace
var _indicator: MeshInstance3D = null
var _was_brushing := false

func _ready() -> void:
	if controller == null:
		controller = get_parent() as XRController3D
	
	if brush_engine == null:
		brush_engine = SplatBrushEngine.new()
		brush_engine.brush_radius = interaction_radius
		add_child(brush_engine)
		
	# Créer un indicateur de pinceau (sphère translucide)
	_indicator = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = interaction_radius
	sphere.height = interaction_radius * 2.0
	_indicator.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_indicator.material_override = mat
	add_child(_indicator)
	
	print("SplatVRBrush: Pinceau VR initialisé pour le contrôleur: ", controller.name if controller else "inconnu")

func _process(_delta: float) -> void:
	if controller == null or not controller.tracker:
		return
		
	# Synchroniser l'indicateur visuel avec les paramètres du pinceau
	if _indicator and _indicator.material_override is StandardMaterial3D:
		var mat = _indicator.material_override as StandardMaterial3D
		mat.albedo_color = brush_engine.brush_color
		mat.albedo_color.a = 0.25
		
		# Ajuster la taille dynamiquement si elle change
		if not is_equal_approx(brush_engine.brush_radius, interaction_radius):
			interaction_radius = brush_engine.brush_radius
			var sphere = _indicator.mesh as SphereMesh
			sphere.radius = interaction_radius
			sphere.height = interaction_radius * 2.0
			
	# Détection de l'appui sur la gâchette (click de gâchette ou valeur analogique)
	var is_brushing := false
	if controller.is_button_pressed(paint_button):
		is_brushing = true
	elif controller.get_float("trigger") > 0.1:
		is_brushing = true
		
	if is_brushing:
		var hit_pos = global_position
		var modified = false
		
		# Appliquer le pinceau sur toutes les surfaces splattables actives
		var splattables = get_tree().get_nodes_in_group("splattables")
		for splattable in splattables:
			if splattable is FoveaSplattable:
				if not brush_engine._is_in_stroke:
					brush_engine.begin_stroke(splattable)
				if brush_engine.apply_brush(splattable, hit_pos):
					modified = true
					
		# Déclencher une vibration si des modifications ont eu lieu
		if modified:
			controller.trigger_haptic_pulse(haptic_action, 120.0, 0.6, 0.04, 0.0)
			
	if not is_brushing and _was_brushing:
		if brush_engine._is_in_stroke:
			brush_engine.commit_stroke()
			
	_was_brushing = is_brushing
