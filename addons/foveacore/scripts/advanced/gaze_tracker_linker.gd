extends Node
class_name GazeTrackerLinker

## GazeTrackerLinker — Connects the OpenXR Eye Tracker to the foveated renderer.
## Performs 3D physics raycasting to determine the exact look-at target.

signal eye_updated(gaze: Vector3, eye: int) # eye: 0 for Left, 1 for Right, 2 for Combined
signal focus_detected(point: Vector3)

@export var eye_tracking_enabled := true
@export var manager: Node = null # FoveaCoreManager
@export var debug_visualization := false

# Reference to the XRInterface
var _xr_interface: XRInterface = null
var _last_gaze_point: Vector3 = Vector3.ZERO

func _ready() -> void:
	_xr_interface = XRServer.find_interface("OpenXR")
	if manager == null:
		manager = get_node_or_null("/root/FoveaCoreManager")
		
	print("GazeTrackerLinker: Attempting to bind to OpenXR interface...")

func _process(_delta: float) -> void:
	if eye_tracking_enabled:
		_update_eye_data()

func _update_eye_data() -> void:
	var gaze_vec := _fetch_openxr_gaze()
	
	# Si aucun tracker n'est trouvé, on utilise la position de la souris pour simuler le regard sur Desktop (Tâche 4)
	if gaze_vec == Vector3.ZERO:
		var camera := get_viewport().get_camera_3d()
		if camera:
			var mouse_pos := get_viewport().get_mouse_position()
			# S'assurer que la souris est dans la fenêtre
			if mouse_pos != Vector2.ZERO and Rect2(Vector2.ZERO, get_viewport().size).has_point(mouse_pos):
				gaze_vec = camera.project_ray_normal(mouse_pos)
			else:
				gaze_vec = -camera.global_transform.basis.z.normalized()
			
	if gaze_vec != Vector3.ZERO:
		_last_gaze_point = _calculate_gaze_world_hit(gaze_vec)
		
		# Link to the foveated renderer in FoveaCoreManager
		if manager and manager._foveated_controller:
			manager._foveated_controller.update_gaze(_last_gaze_point, gaze_vec)
			eye_updated.emit(gaze_vec, 2) # Combined gaze
			focus_detected.emit(_last_gaze_point)

func _calculate_gaze_world_hit(gaze_vec_world: Vector3) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
		
	var ray_origin = camera.global_position
	# Le vecteur de regard étant déjà converti en monde, on le projette à 100 mètres
	var ray_target = ray_origin + (gaze_vec_world * 100.0)
	
	var space_state = camera.get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		
		# Exclure le rig du joueur pour ne pas se heurter à ses propres collisions
		var origin = _find_xr_origin()
		if origin:
			var rids: Array[RID] = []
			_collect_collision_rids(origin, rids)
			query.exclude = rids
			
		var result = space_state.intersect_ray(query)
		if not result.is_empty():
			return result.position
			
	# Si aucun obstacle physique n'est touché, renvoyer la projection à distance maximale
	return ray_target

func _collect_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child in node.get_children():
		_collect_collision_rids(child, rids)

func _fetch_openxr_gaze() -> Vector3:
	# 1. Code path spécifique pour Apple Vision Pro (visionOS / iOS)
	if OS.has_feature("visionos") or OS.get_name() == "iOS":
		var tracker = XRServer.get_tracker("/user/eyes_ext")
		if not tracker:
			tracker = XRServer.get_tracker("eye_gaze")
		if tracker and tracker.has_pose("default"):
			var pose = tracker.get_pose("default")
			var gaze_dir = pose.transform.basis.z * -1.0 # En avant
			
			var origin = _find_xr_origin()
			if origin:
				gaze_dir = origin.global_transform.basis * gaze_dir
			return gaze_dir.normalized()
			
	# 2. OpenXR standard (Meta Quest Pro, etc.)
	# Essayer d'abord la norme moderne "/user/eyes_ext"
	var tracker = XRServer.get_tracker("/user/eyes_ext")
	if not tracker:
		tracker = XRServer.get_tracker("eye_gaze")
		
	if tracker and tracker.has_pose("default"):
		var pose: XRPose = tracker.get_pose("default")
		var gaze_dir: Vector3 = pose.transform.basis.z * -1.0 # En avant dans le repère local
		
		# Convertir le vecteur du tracker (local à l'origine) vers l'espace mondial
		var origin = _find_xr_origin()
		if origin:
			gaze_dir = origin.global_transform.basis * gaze_dir
		return gaze_dir.normalized()
		
	return Vector3.ZERO

func _find_xr_origin() -> XROrigin3D:
	var parent = get_parent()
	while parent:
		if parent is XROrigin3D:
			return parent as XROrigin3D
		parent = parent.get_parent()
	return null
