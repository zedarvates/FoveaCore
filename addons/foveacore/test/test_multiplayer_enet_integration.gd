extends SceneTree

## Starts independent ENet server/client processes and can wait for network I/O.
## Keep it out of the deterministic headless `nogpu` CI group.
const REQUIRES_INTEGRATION := true

const PEER_SCRIPT := "res://addons/foveacore/test/multiplayer_enet_peer.gd"
const TIMEOUT_MSEC := 30000

var _server_pid: int = -1
var _client_pid: int = -1
var _server_result_path: String = ""
var _client_result_path: String = ""


func _init() -> void:
	var token: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	var port: int = 32000 + int(Time.get_ticks_msec() % 20000)
	_server_result_path = ProjectSettings.globalize_path("user://enet_server_%s.json" % token)
	_client_result_path = ProjectSettings.globalize_path("user://enet_client_%s.json" % token)
	_remove_result_files()

	var executable: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	_server_pid = OS.create_process(executable, _peer_arguments(project_path, "server", port, _server_result_path))
	if _server_pid <= 0:
		_finish(false, "failed to start ENet server process")
		return

	await create_timer(0.75).timeout
	_client_pid = OS.create_process(executable, _peer_arguments(project_path, "client", port, _client_result_path))
	if _client_pid <= 0:
		_finish(false, "failed to start ENet client process")
		return

	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(_server_result_path) and FileAccess.file_exists(_client_result_path):
			var server_result: Dictionary = _read_result(_server_result_path)
			var client_result: Dictionary = _read_result(_client_result_path)
			if bool(server_result.get("complete", false)) and bool(client_result.get("complete", false)):
				var ok: bool = bool(server_result.get("ok", false)) and bool(client_result.get("ok", false))
				_finish(ok, "server: %s | client: %s" % [
					server_result.get("detail", "missing result"),
					client_result.get("detail", "missing result")
				])
				return
		if (_server_pid > 0 and not OS.is_process_running(_server_pid)) or (_client_pid > 0 and not OS.is_process_running(_client_pid)):
			# Give a process that just exited one frame to flush its result file.
			await create_timer(0.1).timeout
			if not FileAccess.file_exists(_server_result_path) or not FileAccess.file_exists(_client_result_path):
				_finish(false, "ENet peer exited before producing both results")
				return
		await create_timer(0.05).timeout

	_finish(false, "two-process ENet test timed out (%s)" % _partial_result_detail())


func _peer_arguments(project_path: String, role: String, port: int, result_path: String) -> PackedStringArray:
	return PackedStringArray([
		"--headless",
		"--path", project_path,
		"-s", PEER_SCRIPT,
		"--",
		"--role=" + role,
		"--port=" + str(port),
		"--result=" + result_path
	])


func _read_result(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		# A child may be between truncating and completing its tiny progress file.
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}


func _partial_result_detail() -> String:
	var server_detail: String = "pending"
	var client_detail: String = "pending"
	if FileAccess.file_exists(_server_result_path):
		server_detail = str(_read_result(_server_result_path).get("detail", "invalid result"))
	if FileAccess.file_exists(_client_result_path):
		client_detail = str(_read_result(_client_result_path).get("detail", "invalid result"))
	return "server: %s | client: %s" % [server_detail, client_detail]


func _finish(ok: bool, detail: String) -> void:
	_stop_peer(_client_pid)
	_stop_peer(_server_pid)
	_remove_result_files()
	if ok:
		print("PASS: two-process ENet pose, brush authority, and disconnect cleanup — " + detail)
	else:
		push_error("FAIL: two-process ENet integration — " + detail)
	quit(0 if ok else 1)


func _stop_peer(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _remove_result_files() -> void:
	for path: String in [_server_result_path, _client_result_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
