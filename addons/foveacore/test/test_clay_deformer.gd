## test_clay_deformer.gd
## Script de test/démo pour FoveaClayDeformer
##
## USAGE:
##   1. Créer une scène avec un FoveaCoreSplatRenderer (avec un asset .fovea chargé)
##   2. Ajouter un enfant FoveaClayDeformer (il s'auto-connecte)
##   3. Attacher ce script à un Node dans la même scène
##   4. Assigner `renderer` dans l'inspecteur
##
## SCÉNARIO A - Vent sur feuillage :
##   Un handle de type "push" oscille latéralement en sinus → sway végétal
##
## SCÉNARIO B - Impact / Cratère :
##   Appuyer sur ESPACE déclenche une onde de choc depuis la position du curseur

extends Node

## Assigner le FoveaCoreSplatRenderer de la scène
@export var renderer: FoveaCoreSplatRenderer = null

## Scénario actif : "wind" ou "impact"
@export_enum("wind", "impact", "vortex") var scenario: String = "wind"

## Paramètres vent
@export var wind_origin: Vector3 = Vector3.ZERO
@export var wind_radius: float = 5.0
@export var wind_amplitude: float = 0.6
@export var wind_frequency: float = 0.8

## Paramètres impact
@export var impact_radius: float = 3.0
@export var impact_intensity: float = 2.5
@export var impact_decay_speed: float = 2.0  # À quelle vitesse l'intensité retombe à 0

## Paramètres vortex
@export var vortex_origin: Vector3 = Vector3.ZERO
@export var vortex_radius: float = 4.0
@export var vortex_pull_strength: float = 1.0
@export var vortex_twist_angle: float = PI * 0.4

var _deformer: FoveaClayDeformer = null
var _wind_handle: FoveaClayDeformer.ClayHandle = null
var _impact_handle: FoveaClayDeformer.ClayHandle = null
var _current_impact_intensity: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	if renderer == null:
		push_error("test_clay_deformer: Aucun renderer assigné.")
		return

	# Récupérer le deformer (doit être enfant du renderer)
	_deformer = renderer.get_node_or_null("FoveaClayDeformer") as FoveaClayDeformer
	if _deformer == null:
		# Créer et ajouter dynamiquement si absent
		_deformer = FoveaClayDeformer.new()
		_deformer.name = "FoveaClayDeformer"
		renderer.add_child(_deformer)
		print("test_clay_deformer: FoveaClayDeformer créé dynamiquement.")

	_setup_scenario()

func _setup_scenario() -> void:
	_deformer.clear_handles()

	match scenario:
		"wind":
			_wind_handle = _deformer.add_handle(wind_origin, wind_radius, 1.0)
			_wind_handle.mode = "push"
			_wind_handle.falloff_exponent = 1.5
			print("test_clay_deformer: Scénario VENT activé. Radius=%.1f" % wind_radius)

		"impact":
			# Handle placeholder — mis à jour à chaque impact (SPACE)
			_impact_handle = _deformer.add_handle(Vector3.ZERO, impact_radius, 0.0)
			_impact_handle.mode = "push"
			_impact_handle.falloff_exponent = 3.0
			print("test_clay_deformer: Scénario IMPACT activé. Appuyer ESPACE pour déclencher.")

		"vortex":
			var h := _deformer.add_handle(vortex_origin, vortex_radius, vortex_pull_strength)
			h.mode = "twist"
			h.deformation = Transform3D(Basis.from_euler(Vector3(0, vortex_twist_angle, 0)), Vector3.ZERO)
			h.falloff_exponent = 2.0
			print("test_clay_deformer: Scénario VORTEX activé. Radius=%.1f" % vortex_radius)

func _process(delta: float) -> void:
	_time += delta

	match scenario:
		"wind":
			_update_wind()
		"impact":
			_update_impact(delta)

func _input(event: InputEvent) -> void:
	if scenario == "impact" and event.is_action_pressed("ui_accept"):
		_trigger_impact()

# ─────────────────────────────────────────────
#  Scénario A — Vent
# ─────────────────────────────────────────────

func _update_wind() -> void:
	if _wind_handle == null:
		return
	# Oscillation sinus → sway latéral
	var sway_x := sin(_time * wind_frequency * TAU) * wind_amplitude
	var sway_z := cos(_time * wind_frequency * TAU * 0.6) * wind_amplitude * 0.3
	_wind_handle.deformation = Transform3D(Basis(), Vector3(sway_x, 0.0, sway_z))
	# Force la déformation à s'appliquer
	if _deformer.enabled and renderer.multimesh:
		_deformer.deform_multimesh(renderer.multimesh)

# ─────────────────────────────────────────────
#  Scénario B — Impact / Cratère
# ─────────────────────────────────────────────

func _trigger_impact() -> void:
	if _impact_handle == null or renderer == null:
		return

	# Positionner l'impact à la position de la caméra + 3m devant
	var camera := get_viewport().get_camera_3d()
	if camera:
		var impact_pos := camera.global_position + (-camera.global_transform.basis.z * 3.0)
		_impact_handle.global_position = impact_pos
		_current_impact_intensity = impact_intensity
		print("test_clay_deformer: Impact à ", impact_pos)

func _update_impact(delta: float) -> void:
	if _impact_handle == null:
		return
	if _current_impact_intensity <= 0.0:
		_impact_handle.influence_strength = 0.0
		return

	# Décroissance exponentielle de l'intensité
	_current_impact_intensity = move_toward(_current_impact_intensity, 0.0, delta * impact_decay_speed)
	_impact_handle.influence_strength = _current_impact_intensity
	_impact_handle.deformation = Transform3D(Basis(), Vector3.ONE * _current_impact_intensity)
