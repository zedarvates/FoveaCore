extends Node
class_name FoveaLiveLinkReceiver

## FoveaLiveLinkReceiver — Ingests real-time motion capture data via UDP
## Decodes joint quaternions and facial blendshapes, applying them with slerp smoothing.

signal mocap_frame_received(frame_data: Dictionary)
signal face_blendshapes_received(blendshapes: Dictionary)

@export var port: int = 8766
@export var active: bool = true
@export var target_skeleton: Skeleton3D
@export var lerp_speed: float = 15.0 # Speed of interpolation for smoothing jitter

var _udp := PacketPeerUDP.new()
var _latest_face_data: Dictionary = {}
var _latest_bones_data: Dictionary = {}

func _ready() -> void:
	if active:
		start_listening()

func _exit_tree() -> void:
	stop_listening()

func start_listening() -> void:
	var err: Error = _udp.bind(port)
	if err == OK:
		print("FoveaLiveLinkReceiver: Listening for UDP mocap packets on port ", port)
	else:
		push_error("FoveaLiveLinkReceiver: Failed to bind to UDP port " + str(port) + ". Error: " + str(err))

func stop_listening() -> void:
	if _udp.is_bound():
		_udp.close()
		print("FoveaLiveLinkReceiver: Stopped listening on port ", port)

func _process(delta: float) -> void:
	if not active or not _udp.is_bound():
		return
		
	# Ingest all pending packets
	while _udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = _udp.get_packet()
		var json_str: String = packet.get_string_from_utf8()
		
		var json := JSON.new()
		if json.parse(json_str) == OK:
			var data: Dictionary = json.data
			_parse_mocap_frame(data)
		else:
			push_warning("FoveaLiveLinkReceiver: Received invalid JSON packet.")
			
	# Smoothly apply latest data
	if target_skeleton:
		_apply_bone_rotations(delta)
		
	if not _latest_face_data.is_empty():
		face_blendshapes_received.emit(_latest_face_data)

func _parse_mocap_frame(data: Dictionary) -> void:
	if data.has("face"):
		var face: Dictionary = data["face"]
		for bs_name: String in face:
			_latest_face_data[bs_name] = float(face[bs_name])
			
	if data.has("bones"):
		var bones: Dictionary = data["bones"]
		for bone_name: String in bones:
			var arr: Array = bones[bone_name]
			if arr.size() == 4:
				_latest_bones_data[bone_name] = Quaternion(
					float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3])
				)
				
	mocap_frame_received.emit(data)

func _apply_bone_rotations(delta: float) -> void:
	for bone_name: String in _latest_bones_data:
		var bone_idx: int = target_skeleton.find_bone(bone_name)
		if bone_idx != -1:
			var target_rot: Quaternion = _latest_bones_data[bone_name]
			var current_rot: Quaternion = target_skeleton.get_bone_pose_rotation(bone_idx)
			
			# Smooth interpolation (Slerp) to avoid jittering
			var next_rot: Quaternion = current_rot.slerp(target_rot, clamp(lerp_speed * delta, 0.0, 1.0))
			target_skeleton.set_bone_pose_rotation(bone_idx, next_rot)
