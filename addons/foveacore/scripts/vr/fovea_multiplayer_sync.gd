@tool
extends Node
class_name FoveaMultiplayerSync

## FoveaMultiplayerSync — Replicates VR Rig poses and SplatBrush strokes in multiplayer
## Utilizes Hermite interpolation and dead reckoning via NetworkInterpolator.

# Imports
const NetworkInterpolatorScript = preload("res://addons/foveacore/scripts/network_interpolator.gd")

@export var local_rig: FoveaVRRig = null
@export var remote_rig_scene: PackedScene = null
@export_range(1.0, 120.0, 1.0) var sync_rate_hz: float = 30.0
@export_group("Network Safety")
@export var allow_remote_brush_edits: bool = false
@export var editable_root_path: NodePath = NodePath("..")
@export_range(0.01, 100.0, 0.01) var max_remote_brush_radius: float = 5.0
@export_range(1, 240, 1) var max_pose_updates_per_second: int = 90
@export_range(1, 120, 1) var max_brush_updates_per_second: int = 30
@export_range(1.0, 1000.0, 1.0) var max_pose_speed: float = 100.0
@export_range(10.0, 100000.0, 10.0) var max_world_coordinate: float = 10000.0

var _time_since_last_sync: float = 0.0

# Interpolators
var _head_interpolator: NetworkInterpolator = null
var _left_hand_interpolator: NetworkInterpolator = null
var _right_hand_interpolator: NetworkInterpolator = null

# Map of peer_id (int) -> remote rig wrapper dictionary:
# { peer_id: { "root": Node3D, "head": Node3D, "left": Node3D, "right": Node3D } }
var _remote_rigs: Dictionary = {}

# Keep track of active brushes we've connected to
var _monitored_brushes: Array[SplatBrushEngine] = []

# Velocity estimation variables for local rig
var _prev_head_pos := Vector3.ZERO
var _prev_left_hand_pos := Vector3.ZERO
var _prev_right_hand_pos := Vector3.ZERO
var _last_local_pose_time := 0.0
var _cleanup_timer := 0.0
var _pose_rate_windows: Dictionary = {}
var _brush_rate_windows: Dictionary = {}


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
		
	if multiplayer and multiplayer.has_multiplayer_peer():
		# Spawn rigs for any already connected peers
		for peer_id in multiplayer.get_peers():
			if peer_id != multiplayer.get_unique_id() and not _remote_rigs.has(peer_id):
				_spawn_remote_rig(peer_id)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	_head_interpolator = NetworkInterpolator.new()
	_left_hand_interpolator = NetworkInterpolator.new()
	_right_hand_interpolator = NetworkInterpolator.new()
	
	# Connect to multiplayer signals
	if multiplayer:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
	# Auto-detect local rig if not assigned
	if local_rig == null:
		var rigs = get_tree().get_nodes_in_group("vr_rigs")
		if not rigs.is_empty():
			local_rig = rigs[0] as FoveaVRRig
		else:
			# Try to find anywhere in the scene tree
			local_rig = get_tree().root.find_child("FoveaVRRig", true, false) as FoveaVRRig
			
	# Connect to existing splat brushes
	_scan_for_brushes()
	get_tree().node_added.connect(_on_node_added)
	
	_last_local_pose_time = Time.get_unix_time_from_system()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
		
	_time_since_last_sync += delta
	var interval: float = 1.0 / maxf(sync_rate_hz, 1.0)
	if _time_since_last_sync >= interval:
		_time_since_last_sync = 0.0
		_send_local_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	var current_time := Time.get_unix_time_from_system()
	
	# Process interpolation for each remote rig
	for peer_id in _remote_rigs.keys():
		var rig_data: Dictionary = _remote_rigs[peer_id]
		
		# Get interpolated state
		var head_state = _head_interpolator.get_interpolated_state(peer_id, current_time)
		var left_state = _left_hand_interpolator.get_interpolated_state(peer_id, current_time)
		var right_state = _right_hand_interpolator.get_interpolated_state(peer_id, current_time)
		
		if head_state and is_instance_valid(rig_data.head):
			rig_data.head.global_position = head_state.position
			rig_data.head.global_transform.basis = Basis(head_state.rotation)
			
		if left_state and is_instance_valid(rig_data.left):
			rig_data.left.global_position = left_state.position
			rig_data.left.global_transform.basis = Basis(left_state.rotation)
			
		if right_state and is_instance_valid(rig_data.right):
			rig_data.right.global_position = right_state.position
			rig_data.right.global_transform.basis = Basis(right_state.rotation)
			
	# Periodically clean up old network snapshots
	_cleanup_timer += delta
	if _cleanup_timer >= 1.0:
		_cleanup_timer = 0.0
		_head_interpolator.cleanup()
		_left_hand_interpolator.cleanup()
		_right_hand_interpolator.cleanup()


func _send_local_pose() -> void:
	if local_rig == null:
		return
		
	# Get global transforms
	var head_xf := local_rig.get_hmd_transform()
	var left_xf := local_rig.get_hand_transform(false)
	var right_xf := local_rig.get_hand_transform(true)
	
	# Calculate velocities
	var current_time := Time.get_unix_time_from_system()
	var delta_time := current_time - _last_local_pose_time
	if delta_time <= 0.0:
		delta_time = 0.001
		
	var head_pos := head_xf.origin
	var head_rot := head_xf.basis.get_rotation_quaternion()
	var head_vel := (head_pos - _prev_head_pos) / delta_time
	
	var left_pos := left_xf.origin
	var left_rot := left_xf.basis.get_rotation_quaternion()
	var left_vel := (left_pos - _prev_left_hand_pos) / delta_time
	
	var right_pos := right_xf.origin
	var right_rot := right_xf.basis.get_rotation_quaternion()
	var right_vel := (right_pos - _prev_right_hand_pos) / delta_time
	
	# Save for next frame velocity calculations
	_prev_head_pos = head_pos
	_prev_left_hand_pos = left_pos
	_prev_right_hand_pos = right_pos
	_last_local_pose_time = current_time
	
	# Broadcast pose using unreliable_ordered RPC
	update_peer_pose.rpc(
		head_pos, head_rot, head_vel,
		left_pos, left_rot, left_vel,
		right_pos, right_rot, right_vel,
		current_time
	)


@rpc("any_peer", "unreliable_ordered")
func update_peer_pose(
	head_pos: Vector3, head_rot: Quaternion, head_vel: Vector3,
	left_pos: Vector3, left_rot: Quaternion, left_vel: Vector3,
	right_pos: Vector3, right_rot: Quaternion, right_vel: Vector3,
	timestamp: float
) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var is_remote_call: bool = sender_id != 0
	if sender_id == 0:
		# Fallback for local unit testing / direct calls
		sender_id = 2

	if is_remote_call and not multiplayer.get_peers().has(sender_id):
		push_warning("FoveaMultiplayerSync: Rejected pose from unknown peer %d." % sender_id)
		return
	if not _consume_rate_limit(_pose_rate_windows, sender_id, max_pose_updates_per_second):
		push_warning("FoveaMultiplayerSync: Pose rate limit exceeded by peer %d." % sender_id)
		return
	if not _is_valid_pose_payload(
		head_pos, head_rot, head_vel,
		left_pos, left_rot, left_vel,
		right_pos, right_rot, right_vel,
		timestamp
	):
		push_warning("FoveaMultiplayerSync: Rejected invalid pose payload from peer %d." % sender_id)
		return

	var receive_time: float = Time.get_unix_time_from_system()
	var snapshot_time: float = timestamp
	if absf(timestamp - receive_time) > 5.0:
		snapshot_time = receive_time

	# Ensure rig is spawned
	if not _remote_rigs.has(sender_id):
		_spawn_remote_rig(sender_id)
		
	# Create snapshots for head, left, right hands
	var head_snap = NetworkInterpolatorScript.NetworkSnapshot.new()
	head_snap.player_id = sender_id
	head_snap.position = head_pos
	head_snap.rotation = head_rot.normalized()
	head_snap.velocity = head_vel
	head_snap.timestamp = snapshot_time
	_head_interpolator.receive_snapshot(head_snap)
	
	var left_snap = NetworkInterpolatorScript.NetworkSnapshot.new()
	left_snap.player_id = sender_id
	left_snap.position = left_pos
	left_snap.rotation = left_rot.normalized()
	left_snap.velocity = left_vel
	left_snap.timestamp = snapshot_time
	_left_hand_interpolator.receive_snapshot(left_snap)
	
	var right_snap = NetworkInterpolatorScript.NetworkSnapshot.new()
	right_snap.player_id = sender_id
	right_snap.position = right_pos
	right_snap.rotation = right_rot.normalized()
	right_snap.velocity = right_vel
	right_snap.timestamp = snapshot_time
	_right_hand_interpolator.receive_snapshot(right_snap)


func _spawn_remote_rig(peer_id: int) -> Node3D:
	var rig: Node3D = null
	if remote_rig_scene != null:
		rig = remote_rig_scene.instantiate() as Node3D
	else:
		# Programmatically create a premium, clean representation
		rig = Node3D.new()
		
		# 1. Head
		var head := Node3D.new()
		head.name = "Head"
		var head_mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		head_mesh.mesh = sphere
		
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = Color(0.1, 0.4, 0.9, 0.8) # Sleek cyber blue
		head_mat.roughness = 0.1
		head_mat.metallic = 0.8
		head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		head_mesh.material_override = head_mat
		head.add_child(head_mesh)
		rig.add_child(head)
		
		# 2. Left Hand
		var left := Node3D.new()
		left.name = "LeftHand"
		var left_mesh := MeshInstance3D.new()
		var left_box := BoxMesh.new()
		left_box.size = Vector3(0.08, 0.05, 0.12)
		left_mesh.mesh = left_box
		
		var left_mat := StandardMaterial3D.new()
		left_mat.albedo_color = Color(0.9, 0.1, 0.4, 0.8) # Neon pink
		left_mat.roughness = 0.2
		left_mat.metallic = 0.5
		left_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		left_mesh.material_override = left_mat
		left.add_child(left_mesh)
		rig.add_child(left)
		
		# 3. Right Hand
		var right := Node3D.new()
		right.name = "RightHand"
		var right_mesh := MeshInstance3D.new()
		var right_box := BoxMesh.new()
		right_box.size = Vector3(0.08, 0.05, 0.12)
		right_mesh.mesh = right_box
		
		var right_mat := StandardMaterial3D.new()
		right_mat.albedo_color = Color(0.1, 0.9, 0.4, 0.8) # Cyber neon green
		right_mat.roughness = 0.2
		right_mat.metallic = 0.5
		right_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		right_mesh.material_override = right_mat
		right.add_child(right_mesh)
		rig.add_child(right)
		
	rig.name = "RemoteRig_" + str(peer_id)
	add_child(rig)
	
	# Find sub-nodes
	var head_node := _find_child_by_names(rig, ["Head", "XRCamera3D", "Camera3D", "Camera"])
	var left_node := _find_child_by_names(rig, ["LeftHand", "LeftController", "LeftController3D", "Left_Hand"])
	var right_node := _find_child_by_names(rig, ["RightHand", "RightController", "RightController3D", "Right_Hand"])
	
	# Fallback assignments
	if head_node == null: head_node = rig
	if left_node == null: left_node = rig
	if right_node == null: right_node = rig
	
	_remote_rigs[peer_id] = {
		"root": rig,
		"head": head_node,
		"left": left_node,
		"right": right_node
	}
	
	print("FoveaMultiplayerSync: Spawned remote rig for peer: ", peer_id)
	return rig


func _find_child_by_names(root: Node, names: Array[String]) -> Node3D:
	for n in names:
		var child = root.get_node_or_null(n)
		if child and child is Node3D:
			return child
	# Fallback to recursive search
	for child in root.get_children():
		for n in names:
			if child.name.to_lower() == n.to_lower() and child is Node3D:
				return child
		var found = _find_child_by_names(child, names)
		if found:
			return found
	return null


func _on_peer_connected(peer_id: int) -> void:
	if peer_id != multiplayer.get_unique_id() and not _remote_rigs.has(peer_id):
		_spawn_remote_rig(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_remote_rig(peer_id)
	_pose_rate_windows.erase(peer_id)
	_brush_rate_windows.erase(peer_id)


func _despawn_remote_rig(peer_id: int) -> void:
	if _remote_rigs.has(peer_id):
		var rig_data: Dictionary = _remote_rigs[peer_id]
		if is_instance_valid(rig_data.root):
			rig_data.root.queue_free()
		_remote_rigs.erase(peer_id)
		print("FoveaMultiplayerSync: Despawned remote rig for peer: ", peer_id)


func _on_node_added(node: Node) -> void:
	if node is SplatBrushEngine:
		_connect_brush(node)


func _scan_for_brushes() -> void:
	_scan_node_recursive(get_tree().root)


func _scan_node_recursive(node: Node) -> void:
	if node == null:
		return
	if node is SplatBrushEngine:
		_connect_brush(node)
	for child in node.get_children():
		_scan_node_recursive(child)


func _connect_brush(brush: SplatBrushEngine) -> void:
	if not _monitored_brushes.has(brush):
		_monitored_brushes.append(brush)
		if not brush.brush_applied.is_connected(_on_brush_applied):
			brush.brush_applied.connect(_on_brush_applied.bind(brush))


func _on_brush_applied(splattable_path: NodePath, global_position: Vector3, mode: int, radius: float, color: Color, opacity: float, flow_dir: Vector3, brush: SplatBrushEngine) -> void:
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return

	if multiplayer.is_server():
		receive_brush_stroke.rpc(
			splattable_path, global_position, mode, radius, color, opacity, flow_dir,
			multiplayer.get_unique_id()
		)
	else:
		request_brush_stroke.rpc_id(
			1, splattable_path, global_position, mode, radius, color, opacity, flow_dir
		)


## Compatibility entry point for local tools and unit tests. Network peers must
## use request_brush_stroke; this method intentionally is not exposed as an RPC.
func replicate_brush_stroke(
	splattable_path: NodePath, global_position: Vector3, mode: int,
	radius: float, color: Color, opacity: float, flow_dir: Vector3
) -> void:
	if not _is_valid_brush_payload(splattable_path, global_position, mode, radius, color, opacity, flow_dir):
		push_warning("FoveaMultiplayerSync: Rejected invalid local brush payload.")
		return
	_apply_brush_stroke(splattable_path, global_position, mode, radius, color, opacity, flow_dir)


@rpc("any_peer", "call_remote", "reliable")
func request_brush_stroke(
	splattable_path: NodePath, global_position: Vector3, mode: int,
	radius: float, color: Color, opacity: float, flow_dir: Vector3
) -> void:
	if not multiplayer.is_server():
		push_warning("FoveaMultiplayerSync: Non-authority peer rejected a brush request.")
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0 or not multiplayer.get_peers().has(sender_id):
		push_warning("FoveaMultiplayerSync: Rejected brush request from unknown peer.")
		return
	if not allow_remote_brush_edits:
		push_warning("FoveaMultiplayerSync: Remote brush edits are disabled.")
		return
	if not _consume_rate_limit(_brush_rate_windows, sender_id, max_brush_updates_per_second):
		push_warning("FoveaMultiplayerSync: Brush rate limit exceeded by peer %d." % sender_id)
		return
	if not _is_valid_brush_payload(splattable_path, global_position, mode, radius, color, opacity, flow_dir):
		push_warning("FoveaMultiplayerSync: Rejected invalid brush payload from peer %d." % sender_id)
		return
	if not _apply_brush_stroke(splattable_path, global_position, mode, radius, color, opacity, flow_dir):
		return

	receive_brush_stroke.rpc(
		splattable_path, global_position, mode, radius, color, opacity, flow_dir,
		sender_id
	)


@rpc("authority", "call_remote", "reliable")
func receive_brush_stroke(
	splattable_path: NodePath, global_position: Vector3, mode: int,
	radius: float, color: Color, opacity: float, flow_dir: Vector3,
	origin_peer_id: int
) -> void:
	# The originating client already applied its local brush optimistically.
	if multiplayer.get_unique_id() == origin_peer_id:
		return
	if not _is_valid_brush_payload(splattable_path, global_position, mode, radius, color, opacity, flow_dir):
		push_warning("FoveaMultiplayerSync: Authority sent an invalid brush payload.")
		return
	_apply_brush_stroke(splattable_path, global_position, mode, radius, color, opacity, flow_dir)


func _apply_brush_stroke(
	splattable_path: NodePath, global_position: Vector3, mode: int,
	radius: float, color: Color, opacity: float, flow_dir: Vector3
) -> bool:
	var splattable: FoveaSplattable = _resolve_editable_splattable(splattable_path)
	if splattable == null:
		push_warning("FoveaMultiplayerSync: Brush target is outside editable_root_path: %s" % str(splattable_path))
		return false

	# Apply locally without triggering signals
	var temp_brush := SplatBrushEngine.new()
	temp_brush.is_replicating = true
	temp_brush.brush_mode = mode as SplatBrushEngine.BrushMode
	temp_brush.brush_radius = radius
	temp_brush.brush_color = color
	temp_brush.brush_opacity = opacity
	temp_brush.brush_flow_direction = flow_dir
	
	add_child(temp_brush)
	var success := temp_brush.apply_brush(splattable, global_position)
	temp_brush.queue_free()

	if success and splattable.has_method("_update_local_renderer"):
		splattable.call("_update_local_renderer")
	return success


func _resolve_editable_splattable(splattable_path: NodePath) -> FoveaSplattable:
	var splattable: FoveaSplattable = get_node_or_null(splattable_path) as FoveaSplattable
	var editable_root: Node = get_node_or_null(editable_root_path)
	if splattable == null or editable_root == null:
		return null
	if splattable != editable_root and not editable_root.is_ancestor_of(splattable):
		return null
	return splattable


func _is_valid_pose_payload(
	head_pos: Vector3, head_rot: Quaternion, head_vel: Vector3,
	left_pos: Vector3, left_rot: Quaternion, left_vel: Vector3,
	right_pos: Vector3, right_rot: Quaternion, right_vel: Vector3,
	timestamp: float
) -> bool:
	if not is_finite(timestamp):
		return false
	var positions: Array[Vector3] = [head_pos, left_pos, right_pos]
	var velocities: Array[Vector3] = [head_vel, left_vel, right_vel]
	var rotations: Array[Quaternion] = [head_rot, left_rot, right_rot]
	for position: Vector3 in positions:
		if not _is_finite_vector3(position) or _max_abs_component(position) > max_world_coordinate:
			return false
	for velocity: Vector3 in velocities:
		if not _is_finite_vector3(velocity) or velocity.length() > max_pose_speed:
			return false
	for rotation: Quaternion in rotations:
		if not _is_finite_quaternion(rotation) or rotation.length_squared() <= 0.000001:
			return false
	return true


func _is_valid_brush_payload(
	splattable_path: NodePath, global_position: Vector3, mode: int,
	radius: float, color: Color, opacity: float, flow_dir: Vector3
) -> bool:
	if splattable_path.is_empty() or str(splattable_path).length() > 512:
		return false
	if not _is_finite_vector3(global_position) or _max_abs_component(global_position) > max_world_coordinate:
		return false
	if mode < SplatBrushEngine.BrushMode.PAINT or mode > SplatBrushEngine.BrushMode.SCALE:
		return false
	if not is_finite(radius) or radius <= 0.0 or radius > max_remote_brush_radius:
		return false
	if not _is_finite_color(color) or not is_finite(opacity) or opacity < 0.0 or opacity > 1.0:
		return false
	if not _is_finite_vector3(flow_dir) or flow_dir.length() > max_pose_speed:
		return false
	return true


func _consume_rate_limit(windows: Dictionary, peer_id: int, max_events: int) -> bool:
	if peer_id <= 0:
		return true
	var now_msec: int = Time.get_ticks_msec()
	var state: Dictionary = windows.get(peer_id, {"start_msec": now_msec, "count": 0})
	if now_msec - int(state.get("start_msec", now_msec)) >= 1000:
		state = {"start_msec": now_msec, "count": 0}
	if int(state.get("count", 0)) >= maxi(max_events, 1):
		return false
	state["count"] = int(state.get("count", 0)) + 1
	windows[peer_id] = state
	return true


static func _is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _is_finite_quaternion(value: Quaternion) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)


static func _is_finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)


static func _max_abs_component(value: Vector3) -> float:
	return maxf(absf(value.x), maxf(absf(value.y), absf(value.z)))
