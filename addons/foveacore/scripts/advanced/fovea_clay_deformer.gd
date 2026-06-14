class_name FoveaClayDeformer
extends Node3D

## FoveaEngine — Clay Deformer
## Déformation spatiale interactive des Gaussian Splats sans squelette.
## Inspiré du concept Clay Transforms : chaque ClayHandle est une zone d'influence
## qui attire, repousse, écrase ou déforme les splats environnants.
##
## Usage :
##   1. Ajouter FoveaClayDeformer comme enfant d'un FoveaCoreSplatRenderer.
##   2. Appeler add_handle() pour créer des zones d'influence.
##   3. Le deformer s'enregistre automatiquement sur le renderer parent.

# ─────────────────────────────────────────────
#  Inner Class: ClayHandle
# ─────────────────────────────────────────────

class ClayHandle:
	## Position globale du handle dans l'espace monde
	var global_position: Vector3 = Vector3.ZERO

	## Rayon de la zone d'influence (en unités Godot)
	var radius: float = 2.0

	## Force de l'influence (0.0 = aucun effet, 1.0 = effet total)
	var influence_strength: float = 1.0

	## Transformation locale appliquée aux splats dans la zone
	## - translate : déplace les splats (push/pull)
	## - rotate    : fait pivoter la zone (swirl / twirl)
	## - scale     : compresse ou gonfle les splats (crush / inflate)
	var deformation: Transform3D = Transform3D.IDENTITY

	## Type de déformation
	## "push"    : répulsion depuis le centre (explosion, craters)
	## "pull"    : attraction vers le centre (vortex)
	## "twist"   : rotation autour de l'axe Y local (swirl)
	## "flatten" : aplatissement vertical (écrasement)
	var mode: String = "push"

	## Falloff curve exponent (1.0 = linéaire, 2.0 = smooth, 3.0 = très doux)
	var falloff_exponent: float = 2.0

	## Si true, ignore les splats déjà à leur position d'origine (optimisation)
	var skip_stationary: bool = false

	func _init(pos: Vector3, r: float = 2.0, strength: float = 1.0) -> void:
		global_position = pos
		radius = r
		influence_strength = strength

	## Calcule le poids d'influence pour un splat à la position world_pos
	func get_influence_weight(world_pos: Vector3) -> float:
		var dist := global_position.distance_to(world_pos)
		if dist >= radius:
			return 0.0
		var t := 1.0 - (dist / radius)
		return pow(t, falloff_exponent) * influence_strength

	## Applique la déformation du handle à un Transform3D d'un splat
	func apply_to_transform(original: Transform3D, weight: float) -> Transform3D:
		if weight <= 0.0:
			return original

		var world_pos := original.origin
		var delta := world_pos - global_position

		match mode:
			"push":
				# Repousser radialmente depuis le centre du handle
				var push_dir := delta.normalized() if delta.length_squared() > 0.0001 else Vector3.UP
				var push_amount := deformation.origin.length() if deformation.origin != Vector3.ZERO else 1.0
				var new_origin := world_pos + push_dir * push_amount * weight
				return Transform3D(original.basis, new_origin)

			"pull":
				# Attirer vers le centre du handle
				var pull_dir := -delta.normalized() if delta.length_squared() > 0.0001 else Vector3.DOWN
				var pull_amount := deformation.origin.length() if deformation.origin != Vector3.ZERO else 1.0
				var new_origin := world_pos + pull_dir * pull_amount * weight
				return Transform3D(original.basis, new_origin)

			"twist":
				# Rotation autour de l'axe Y centré sur le handle
				var angle := deformation.basis.get_euler().y * weight
				var rotated_delta := delta.rotated(Vector3.UP, angle)
				var new_origin := global_position + rotated_delta
				var new_basis := original.basis.rotated(Vector3.UP, angle)
				return Transform3D(new_basis, new_origin)

			"flatten":
				# Aplatissement vertical : compresser l'axe Y vers la hauteur du handle
				var target_y := global_position.y + deformation.origin.y
				var new_y := lerp(world_pos.y, target_y, weight)
				var new_origin := Vector3(world_pos.x, new_y, world_pos.z)
				# Compresser aussi l'échelle Y du basis
				var s := lerp(1.0, 0.1, weight)
				var new_basis := original.basis.scaled(Vector3(1.0, s, 1.0))
				return Transform3D(new_basis, new_origin)

			_:
				# Fallback : interpolation directe avec la transformation du handle
				return original.interpolate_with(deformation, weight)


# ─────────────────────────────────────────────
#  FoveaClayDeformer Properties
# ─────────────────────────────────────────────

## Si false, la déformation est suspendue (économie CPU)
@export var enabled: bool = true

## Limiter le nombre de splats traités par frame pour les perfs
## 0 = pas de limite (process tout d'un coup)
@export var max_splats_per_frame: int = 0

## Afficher des gizmos de debug en éditeur (sphères de rayon)
@export var debug_draw: bool = false

## Handles actifs
var _handles: Array[ClayHandle] = []

## Cache des transforms originaux (non déformés)
## Clé: MultiMesh RID.get_id(), Valeur: Array[Transform3D]
var _original_transforms: Dictionary[int, PackedFloat32Array] = {}

## Référence au renderer parent (si FoveaClayDeformer est enfant d'un SplatRenderer)
var _renderer: FoveaCoreSplatRenderer = null

# ─────────────────────────────────────────────
#  Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	# Tentative d'auto-connexion au renderer parent.
	# Le FoveaCoreSplatRenderer est le driver exclusif de deform_multimesh() :
	# son _process() appelle deformer.deform_multimesh() une seule fois par frame.
	# NE PAS ajouter de _process() ici pour éviter un double appel (BUG-01).
	var parent := get_parent()
	if parent is FoveaCoreSplatRenderer:
		_renderer = parent
		_renderer.deformer = self
		print("FoveaClayDeformer: Auto-connecté à FoveaCoreSplatRenderer '%s'" % parent.name)

# ─────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────

## Créer et enregistrer un nouveau ClayHandle
func add_handle(position: Vector3, radius: float = 2.0, strength: float = 1.0) -> ClayHandle:
	var handle := ClayHandle.new(position, radius, strength)
	_handles.append(handle)
	return handle

## Supprimer un handle existant
func remove_handle(handle: ClayHandle) -> void:
	_handles.erase(handle)

## Supprimer tous les handles
func clear_handles() -> void:
	_handles.clear()

## Obtenir tous les handles actifs
func get_handles() -> Array[ClayHandle]:
	return _handles

## Lire le cache de transforms originaux pour un MultiMesh donné.
## Utile pour que le renderer puisse l'alimenter après le chargement des splats.
func set_original_transforms(mm: MultiMesh, transforms: Array[Transform3D]) -> void:
	var count := transforms.size()
	var arr := PackedFloat32Array()
	arr.resize(count * 12)
	for i in count:
		var xf := transforms[i]
		var b := xf.basis
		var o := xf.origin
		var base := i * 12
		arr[base + 0] = b.x.x
		arr[base + 1] = b.y.x
		arr[base + 2] = b.z.x
		arr[base + 3] = o.x
		arr[base + 4] = b.x.y
		arr[base + 5] = b.y.y
		arr[base + 6] = b.z.y
		arr[base + 7] = o.y
		arr[base + 8] = b.x.z
		arr[base + 9] = b.y.z
		arr[base + 10] = b.z.z
		arr[base + 11] = o.z
	_original_transforms[mm.get_instance_id()] = arr

## Forcer un recalcul des transforms originaux depuis le MultiMesh actuel
## (snapshot de l'état courant comme "repos")
func snapshot_originals(mm: MultiMesh) -> void:
	var count := mm.instance_count
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf := mm.buffer
	var arr := PackedFloat32Array()
	arr.resize(count * 12)
	for i in count:
		var src := i * stride
		var dest := i * 12
		for j in 12:
			arr[dest + j] = buf[src + j]
	_original_transforms[mm.get_instance_id()] = arr
	print("FoveaClayDeformer: Snapshot de %d transforms originaux." % count)

## Réinitialiser le MultiMesh à ses transforms d'origine (annuler la déformation)
func reset_to_originals(mm: MultiMesh) -> void:
	var key := mm.get_instance_id()
	if not _original_transforms.has(key):
		push_warning("FoveaClayDeformer: Aucun snapshot disponible pour ce MultiMesh.")
		return
	var originals: PackedFloat32Array = _original_transforms[key]
	var count := mini(mm.instance_count, originals.size() / 12)
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf := mm.buffer
	for i in count:
		var src := i * 12
		var dest := i * stride
		for j in 12:
			buf[dest + j] = originals[src + j]
	mm.buffer = buf

func _read_transform(arr: PackedFloat32Array, index: int) -> Transform3D:
	var base := index * 12
	var x_axis := Vector3(arr[base + 0], arr[base + 4], arr[base + 8])
	var y_axis := Vector3(arr[base + 1], arr[base + 5], arr[base + 9])
	var z_axis := Vector3(arr[base + 2], arr[base + 6], arr[base + 10])
	var origin := Vector3(arr[base + 3], arr[base + 7], arr[base + 11])
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)

# ─────────────────────────────────────────────
#  Deformation Engine
# ─────────────────────────────────────────────

## Déformer un MultiMesh selon tous les handles actifs.
## Utilise les transforms originaux comme base non destructive.
func deform_multimesh(mm: MultiMesh) -> void:
	if _handles.is_empty():
		return

	var key := mm.get_instance_id()
	var count := mm.instance_count

	# Créer le snapshot initial si nécessaire
	if not _original_transforms.has(key):
		snapshot_originals(mm)
		return  # On attend le prochain frame pour travailler sur des données fraîches

	var originals: PackedFloat32Array = _original_transforms[key]
	var limit := count if max_splats_per_frame <= 0 else mini(count, max_splats_per_frame)

	# Écriture bulk : modification d'une copie du buffer puis une seule affectation GPU
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf: PackedFloat32Array = mm.buffer

	for i in limit:
		if i >= originals.size() / 12:
			break

		var original_xf := _read_transform(originals, i)
		var world_pos: Vector3 = original_xf.origin

		# Accumuler toutes les contributions des handles
		var final_xf := original_xf
		for handle in _handles:
			var weight := handle.get_influence_weight(world_pos)
			if weight > 0.0:
				final_xf = handle.apply_to_transform(final_xf, weight)

		FoveaMultiMeshBulk.write_transform(buf, i * stride, final_xf)

	mm.buffer = buf


# ─────────────────────────────────────────────
#  Convenience Factory Methods
# ─────────────────────────────────────────────

## Créer un handle de type "wind" : oscillation latérale animée par le temps
## À appeler dans _process() avec l'heure courante.
static func make_wind_handle(origin: Vector3, radius: float, time: float,
							 amplitude: float = 0.5, frequency: float = 1.5) -> ClayHandle:
	var h := ClayHandle.new(origin, radius, 1.0)
	h.mode = "push"
	var sway := sin(time * frequency * TAU) * amplitude
	h.deformation = Transform3D(Basis(), Vector3(sway, 0.0, 0.0))
	h.falloff_exponent = 1.5
	return h

## Créer un handle de type "impact" : onde de choc sphérique depuis un point
static func make_impact_handle(hit_point: Vector3, blast_radius: float,
							   intensity: float = 2.0) -> ClayHandle:
	var h := ClayHandle.new(hit_point, blast_radius, intensity)
	h.mode = "push"
	h.deformation = Transform3D(Basis(), Vector3(intensity, intensity, intensity))
	h.falloff_exponent = 3.0
	return h

## Créer un handle de type "vortex" : aspiration en spirale vers un centre
static func make_vortex_handle(center: Vector3, radius: float,
							   pull_strength: float = 1.5, twist_angle: float = PI * 0.5) -> ClayHandle:
	var h := ClayHandle.new(center, radius, pull_strength)
	h.mode = "twist"
	h.deformation = Transform3D(Basis.from_euler(Vector3(0.0, twist_angle, 0.0)), Vector3.ZERO)
	h.falloff_exponent = 2.0
	return h
