class_name FoveaHermesBridge
extends Node

## FoveaEngine — Hermes/Blender Bridge (items 272-283)
## WebSocket server allowing Hermes Agent and Blender addon to
## communicate with FoveaEngine: generate, edit, query assets.

signal client_connected(client_id: int)
signal client_disconnected(client_id: int)
signal request_received(client_id: int, request: Dictionary)

@export var port: int = 8765
@export var auth_token: String = ""
@export var max_clients: int = 5
@export var sandbox_enabled: bool = true  # Whitelist-only operations

var _server: WebSocketServer = WebSocketServer.new()
var _clients: Dictionary = {}  # client_id → WebSocketPeer

# Whitelist of allowed operations (sandbox, item 280)
const ALLOWED_OPS: Dictionary = {
	"ping": {"args": [], "response": {"pong": true}},
	"get_scene_info": {"args": [], "response": {"nodes": [], "assets": []}},
	"generate_splats": {"args": ["mesh_path", "density"], "response": {"splat_path": "", "count": 0}},
	"edit_transform": {"args": ["node_path", "position", "rotation"], "response": {"success": false}},
	"query_asset": {"args": ["asset_path"], "response": {"splat_count": 0, "bounds": {}}},
	"get_stats": {"args": [], "response": {"fps": 0, "splat_count": 0, "vram_mb": 0}},
}

func _ready() -> void:
	_server.connect("client_connected", _on_connected)
	_server.connect("client_disconnected", _on_disconnected)
	_server.connect("data_received", _on_data)
	
	var err = _server.listen(port, PackedStringArray(), false)
	if err == OK:
		print("FoveaHermesBridge: WebSocket server on ws://0.0.0.0:%d" % port)
	else:
		push_error("FoveaHermesBridge: Failed to start server: " + error_string(err))

func _process(delta: float) -> void:
	_server.poll()

func _on_connected(client_id: int, protocol: String) -> void:
	print("FoveaHermesBridge: Client %d connected" % client_id)
	_clients[client_id] = _server.get_peer(client_id)
	emit_signal("client_connected", client_id)

func _on_disconnected(client_id: int, was_clean: bool) -> void:
	print("FoveaHermesBridge: Client %d disconnected" % client_id)
	_clients.erase(client_id)
	emit_signal("client_disconnected", client_id)

func _on_data(client_id: int) -> void:
	var peer = _clients.get(client_id)
	if not peer: return
	
	while peer.get_available_packet_count() > 0:
		var pkt = peer.get_packet().get_string_from_utf8()
		var parsed = _parse_request(pkt, client_id)
		if parsed:
			_send_response(client_id, parsed)

func _parse_request(data: String, client_id: int) -> Dictionary:
	var json = JSON.new()
	var err = json.parse(data)
	if err != OK:
		_send_error(client_id, "Invalid JSON: " + json.get_error_message())
		return {}
	
	var req = json.data
	if typeof(req) != TYPE_DICTIONARY:
		_send_error(client_id, "Request must be a JSON object")
		return {}
	
	var op = req.get("op", "")
	if op == "":
		_send_error(client_id, "Missing 'op' field")
		return {}
	
	if sandbox_enabled and not ALLOWED_OPS.has(op):
		_send_error(client_id, "Operation '%s' not allowed in sandbox mode" % op)
		return {}
	
	var request_id = req.get("id", 0)
	return _handle_op(op, req.get("args", {}), client_id, request_id)

func _handle_op(op: String, args: Dictionary, client_id: int, req_id: int) -> Dictionary:
	var response = {"id": req_id, "op": op, "success": true}
	
	match op:
		"ping":
			response["data"] = {"pong": true, "time": Time.get_ticks_msec()}
		"get_scene_info":
			response["data"] = _get_scene_info()
		"get_stats":
			response["data"] = _get_stats()
		_:
			response["success"] = false
			response["error"] = "Operation not implemented"
	
	return response

func _get_scene_info() -> Dictionary:
	var info = {"nodes": [], "assets": []}
	var root = get_tree().root
	for child in root.get_children():
		if child.has_method("get_splat_count"):
			info["assets"].append({
				"name": child.name, 
				"splat_count": child.get_splat_count() if child.has_method("get_splat_count") else 0
			})
		info["nodes"].append(child.name)
	return info

func _get_stats() -> Dictionary:
	var engine = Engine.get_frames_per_second()
	return {
		"fps": engine,
		"time": Time.get_ticks_msec(),
		"node_count": get_tree().get_node_count(),
	}

func _send_response(client_id: int, response: Dictionary) -> void:
	var peer = _clients.get(client_id)
	if peer:
		peer.put_packet(JSON.stringify(response).to_utf8_buffer())

func _send_error(client_id: int, message: String) -> void:
	var peer = _clients.get(client_id)
	if peer:
		var err_response = JSON.stringify({"error": message})
		peer.put_packet(err_response.to_utf8_buffer())

func _exit_tree() -> void:
	_server.stop()
	print("FoveaHermesBridge: Server stopped")
