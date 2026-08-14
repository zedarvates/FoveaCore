extends SceneTree

const MULTIPLAYER_SYNC := preload("res://addons/foveacore/scripts/vr/fovea_multiplayer_sync.gd")
const FOVEA_SPLATTABLE := preload("res://addons/foveacore/scripts/fovea_splattable.gd")
const GAUSSIAN_SPLAT := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

const EXPECTED_HEAD_POSITION := Vector3(1.0, 2.0, 3.0)
const SERVER_ID := 1
const DEFAULT_TIMEOUT_MSEC := 12000

var _role: String = ""
var _port: int = 0
var _result_path: String = ""
var _sync: FoveaMultiplayerSync = null
var _splattable: FoveaSplattable = null
var _peer: ENetMultiplayerPeer = null
var _peer_disconnected: bool = false
var _client_peer_id: int = 0


func _init() -> void:
	_parse_arguments()
	if _role not in ["server", "client"] or _port <= 0 or _result_path.is_empty():
		_finish(false, "invalid peer arguments")
		return

	_write_progress("arguments parsed")
	# Let project autoloads finish entering the SceneTree before adding the
	# deterministic shared test nodes. Adding them from SceneTree._init() can
	# otherwise interleave with autoload registration and stall startup.
	await process_frame
	_write_progress("autoloads ready")
	_setup_shared_scene()
	_write_progress("shared scene ready")
	if _role == "server":
		await _run_server()
	else:
		await _run_client()


func _parse_arguments() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument: String in arguments:
		if argument.begins_with("--role="):
			_role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			_port = argument.trim_prefix("--port=").to_int()
		elif argument.begins_with("--result="):
			_result_path = argument.trim_prefix("--result=")


func _setup_shared_scene() -> void:
	_splattable = FOVEA_SPLATTABLE.new()
	_splattable.name = "SharedSplat"
	var splat: GaussianSplat = GAUSSIAN_SPLAT.new(Vector3.ZERO)
	splat.color = Color.BLACK
	splat.opacity = 1.0
	_splattable.loaded_splats.append(splat)
	root.add_child(_splattable)

	_sync = MULTIPLAYER_SYNC.new()
	_sync.name = "MultiplayerSync"
	_sync.allow_remote_brush_edits = _role == "server"
	_sync.editable_root_path = NodePath("..")
	root.add_child(_sync)


func _run_server() -> void:
	_peer = ENetMultiplayerPeer.new()
	var create_error: Error = _peer.create_server(_port, 1)
	if create_error != OK:
		_finish(false, "create_server failed: %d" % create_error)
		return
	root.multiplayer.multiplayer_peer = _peer
	_write_progress("server listening")

	var deadline: int = Time.get_ticks_msec() + DEFAULT_TIMEOUT_MSEC
	var pose_received: bool = false
	var client_brush_received: bool = false
	var authority_brush_sent: bool = false
	root.multiplayer.peer_connected.connect(func(peer_id: int) -> void:
		if peer_id != SERVER_ID:
			_client_peer_id = peer_id
			_write_progress("server connected peer %d" % peer_id)
	)
	root.multiplayer.peer_disconnected.connect(func(peer_id: int) -> void:
		if peer_id == _client_peer_id:
			_peer_disconnected = true
	)

	while Time.get_ticks_msec() < deadline:
		if _client_peer_id > 0 and _sync._remote_rigs.has(_client_peer_id):
			var state: NetworkInterpolator.RemotePlayerState = _sync._head_interpolator.get_interpolated_state(
				_client_peer_id, Time.get_unix_time_from_system()
			)
			pose_received = state != null and state.position.is_equal_approx(EXPECTED_HEAD_POSITION)

		var server_splat: GaussianSplat = _splattable.loaded_splats[0]
		client_brush_received = client_brush_received or server_splat.color == Color.GREEN
		if pose_received and client_brush_received and not authority_brush_sent:
			_sync.replicate_brush_stroke(
				_splattable.get_path(), Vector3.ZERO,
				SplatBrushEngine.BrushMode.PAINT, 1.0, Color.BLUE, 1.0, Vector3.UP
			)
			_sync.receive_brush_stroke.rpc(
				_splattable.get_path(), Vector3.ZERO,
				SplatBrushEngine.BrushMode.PAINT, 1.0, Color.BLUE, 1.0, Vector3.UP,
				SERVER_ID
			)
			authority_brush_sent = true

		if authority_brush_sent and _peer_disconnected:
			await process_frame
			var cleaned_up: bool = not _sync._remote_rigs.has(_client_peer_id)
			_finish(
				cleaned_up,
				"server pose=%s client_brush=%s authority_brush=%s disconnect_cleanup=%s" % [
					pose_received, client_brush_received, authority_brush_sent, cleaned_up
				]
			)
			return
		await create_timer(0.02).timeout

	_finish(false, "server timeout: pose=%s brush=%s authority=%s disconnected=%s" % [
		pose_received, client_brush_received, authority_brush_sent, _peer_disconnected
	])


func _run_client() -> void:
	_peer = ENetMultiplayerPeer.new()
	var create_error: Error = _peer.create_client("127.0.0.1", _port)
	if create_error != OK:
		_finish(false, "create_client failed: %d" % create_error)
		return
	root.multiplayer.multiplayer_peer = _peer
	_write_progress("client connecting")

	var deadline: int = Time.get_ticks_msec() + DEFAULT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline and root.multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		await create_timer(0.02).timeout
	if root.multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_finish(false, "client connection timeout")
		return
	_write_progress("client connected")

	_sync.update_peer_pose.rpc_id(
		SERVER_ID,
		EXPECTED_HEAD_POSITION, Quaternion.IDENTITY, Vector3.ZERO,
		Vector3(-0.2, 1.0, -0.5), Quaternion.IDENTITY, Vector3.ZERO,
		Vector3(0.2, 1.0, -0.5), Quaternion.IDENTITY, Vector3.ZERO,
		Time.get_unix_time_from_system()
	)

	# Mirror the runtime's optimistic local edit before requesting authority.
	_sync.replicate_brush_stroke(
		_splattable.get_path(), Vector3.ZERO,
		SplatBrushEngine.BrushMode.PAINT, 1.0, Color.GREEN, 1.0, Vector3.UP
	)
	_sync.request_brush_stroke.rpc_id(
		SERVER_ID, _splattable.get_path(), Vector3.ZERO,
		SplatBrushEngine.BrushMode.PAINT, 1.0, Color.GREEN, 1.0, Vector3.UP
	)
	_write_progress("client sent pose and brush")

	while Time.get_ticks_msec() < deadline:
		var client_splat: GaussianSplat = _splattable.loaded_splats[0]
		if client_splat.color == Color.BLUE:
			_write_result(true, "client received authority brush")
			_peer.close()
			await create_timer(0.1).timeout
			quit(0)
			return
		await create_timer(0.02).timeout

	_finish(false, "client did not receive authority brush")


func _finish(ok: bool, detail: String) -> void:
	_write_result(ok, detail)
	if _peer != null:
		_peer.close()
	quit(0 if ok else 1)


func _write_result(ok: bool, detail: String) -> void:
	_write_status(ok, detail, true)


func _write_progress(detail: String) -> void:
	_write_status(false, detail, false)


func _write_status(ok: bool, detail: String, complete: bool) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		push_error("ENet peer could not write result: " + _result_path)
		return
	file.store_string(JSON.stringify({
		"ok": ok,
		"complete": complete,
		"role": _role,
		"detail": detail
	}))
	file.close()
