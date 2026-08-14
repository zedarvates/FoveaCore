extends "res://addons/foveacore/scripts/advanced/neural_style_bridge.gd"
class_name ComfyUISplatBridge

## ComfyUI workflow bridge for importing generated Gaussian-splat artifacts.
##
## The caller supplies an API-format ComfyUI workflow and the ID of its
## LoadImage node. The bridge uploads the source image, submits the workflow,
## polls its history, downloads the first supported artifact, validates it, and
## optionally assigns it to a FoveaSplat3D node.

const SUPPORTED_ARTIFACT_EXTENSIONS := ["fovea", "ply", "splat"]
const MAX_PATH_LENGTH: int = 1024
const MAX_ARTIFACT_SCAN_DEPTH: int = 8
const SPLAT_STRIDE: int = 32

@export_range(1, 600, 1) var max_poll_attempts: int = 120
@export_range(0.1, 10.0, 0.1) var poll_interval_seconds: float = 1.0


## Runs a ComfyUI image-to-splat workflow and imports its output.
##
## [param workflow] may be either a raw API prompt graph or a payload containing
## a [code]prompt[/code] dictionary. [param destination_path] must stay under
## [code]res://[/code] or [code]user://[/code] and must not already exist.
## [param callback] receives a dictionary with [code]ok[/code], and either
## [code]path[/code]/[code]artifact[/code] or [code]error[/code].
func generate_splat_from_image(
		input_image: Image,
		workflow: Dictionary,
		load_image_node_id: String,
		destination_path: String,
		target: FoveaSplat3D,
		callback: Callable = Callable()
) -> void:
	if input_image == null:
		_finish(callback, {"ok": false, "error": "Input image is null"})
		return

	var destination_error: String = validate_destination_path(destination_path)
	if not destination_error.is_empty():
		_finish(callback, {"ok": false, "error": destination_error})
		return

	var image_bytes: PackedByteArray = input_image.save_png_to_buffer()
	if image_bytes.is_empty():
		_finish(callback, {"ok": false, "error": "Could not encode the input image as PNG"})
		return

	var tree: SceneTree = _scene_tree()
	if tree == null:
		_finish(callback, {"ok": false, "error": "No SceneTree is available"})
		return

	var filename: String = "fovea_comfy_input_%d.png" % Time.get_ticks_msec()
	var boundary: String = "GodotBoundary%d" % Time.get_ticks_msec()
	var body: PackedByteArray = _multipart_image_body(image_bytes, filename, boundary)
	var headers: Array[String] = [
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"Content-Length: " + str(body.size()),
	]
	var uploader := HTTPRequest.new()
	tree.root.add_child(uploader)
	_active_http_requests.append(uploader)
	uploader.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
			_cleanup_request(uploader)
			if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
				_finish(callback, {
					"ok": false,
					"error": "ComfyUI image upload failed (result %d, HTTP %d)" % [result, response_code],
				})
				return
			var response: Variant = JSON.parse_string(response_body.get_string_from_utf8())
			if not response is Dictionary:
				_finish(callback, {"ok": false, "error": "ComfyUI returned invalid upload JSON"})
				return
			var uploaded_name: String = str((response as Dictionary).get("name", ""))
			if uploaded_name.is_empty():
				_finish(callback, {"ok": false, "error": "ComfyUI upload response has no image name"})
				return
			var prepared: Dictionary = prepare_workflow_with_uploaded_image(
				workflow,
				load_image_node_id,
				uploaded_name
			)
			if not bool(prepared.get("ok", false)):
				_finish(callback, prepared)
				return
			submit_splat_workflow(
				prepared["workflow"],
				destination_path,
				target,
				callback
			)
	)

	var request_error: Error = uploader.request_raw(
		_endpoint("/upload/image"),
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if request_error != OK:
		_cleanup_request(uploader)
		_finish(callback, {
			"ok": false,
			"error": "Could not start the ComfyUI image upload (%d)" % request_error,
		})


## Submits an already prepared ComfyUI workflow and imports its splat output.
func submit_splat_workflow(
		workflow: Dictionary,
		destination_path: String,
		target: FoveaSplat3D,
		callback: Callable = Callable()
) -> void:
	var destination_error: String = validate_destination_path(destination_path)
	if not destination_error.is_empty():
		_finish(callback, {"ok": false, "error": destination_error})
		return

	var payload_result: Dictionary = build_prompt_payload(workflow)
	if not bool(payload_result.get("ok", false)):
		_finish(callback, payload_result)
		return

	var tree: SceneTree = _scene_tree()
	if tree == null:
		_finish(callback, {"ok": false, "error": "No SceneTree is available"})
		return

	var prompter := HTTPRequest.new()
	tree.root.add_child(prompter)
	_active_http_requests.append(prompter)
	prompter.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
			_cleanup_request(prompter)
			if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
				_finish(callback, {
					"ok": false,
					"error": "ComfyUI prompt submission failed (result %d, HTTP %d)" % [result, response_code],
				})
				return
			var response: Variant = JSON.parse_string(response_body.get_string_from_utf8())
			if not response is Dictionary:
				_finish(callback, {"ok": false, "error": "ComfyUI returned invalid prompt JSON"})
				return
			var prompt_id: String = str((response as Dictionary).get("prompt_id", ""))
			if prompt_id.is_empty():
				_finish(callback, {"ok": false, "error": "ComfyUI response has no prompt_id"})
				return
			_poll_splat_artifact(prompt_id, destination_path, target, callback, tree, 0)
	)

	var request_error: Error = prompter.request(
		_endpoint("/prompt"),
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload_result["payload"])
	)
	if request_error != OK:
		_cleanup_request(prompter)
		_finish(callback, {
			"ok": false,
			"error": "Could not start the ComfyUI prompt request (%d)" % request_error,
		})


## Returns a deep-copied workflow with the uploaded image injected into the
## requested LoadImage node. The caller's dictionary is never mutated.
func prepare_workflow_with_uploaded_image(
		workflow: Dictionary,
		load_image_node_id: String,
		uploaded_name: String
) -> Dictionary:
	if load_image_node_id.is_empty():
		return {"ok": false, "error": "LoadImage node ID is required"}
	if uploaded_name.is_empty():
		return {"ok": false, "error": "Uploaded image name is required"}

	var payload_result: Dictionary = build_prompt_payload(workflow)
	if not bool(payload_result.get("ok", false)):
		return payload_result
	var payload: Dictionary = payload_result["payload"]
	var graph: Dictionary = payload["prompt"]
	var node_key: Variant = load_image_node_id
	if not graph.has(node_key) and load_image_node_id.is_valid_int():
		var numeric_key: int = load_image_node_id.to_int()
		if graph.has(numeric_key):
			node_key = numeric_key
	if not graph.has(node_key):
		return {"ok": false, "error": "LoadImage node not found: " + load_image_node_id}
	var node_value: Variant = graph[node_key]
	if not node_value is Dictionary:
		return {"ok": false, "error": "LoadImage node is not a dictionary"}
	var node: Dictionary = node_value
	var inputs_value: Variant = node.get("inputs", {})
	if not inputs_value is Dictionary:
		return {"ok": false, "error": "LoadImage node inputs are not a dictionary"}
	var inputs: Dictionary = inputs_value
	inputs["image"] = uploaded_name
	inputs["upload"] = "image"
	node["inputs"] = inputs
	graph[node_key] = node
	payload["prompt"] = graph
	return {"ok": true, "workflow": payload}


## Normalizes a raw ComfyUI API graph or an existing prompt payload.
func build_prompt_payload(workflow: Dictionary) -> Dictionary:
	if workflow.is_empty():
		return {"ok": false, "error": "ComfyUI workflow is empty"}
	var payload: Dictionary
	if workflow.has("prompt"):
		payload = workflow.duplicate(true)
		if not payload["prompt"] is Dictionary or (payload["prompt"] as Dictionary).is_empty():
			return {"ok": false, "error": "ComfyUI prompt graph is empty or invalid"}
	else:
		payload = {"prompt": workflow.duplicate(true)}
	return {"ok": true, "payload": payload}


## Finds the first .fovea, .ply, or .splat descriptor in arbitrary ComfyUI
## output nodes without relying on a workflow-specific node ID or output key.
func find_first_splat_artifact(history_entry: Dictionary) -> Dictionary:
	var outputs_value: Variant = history_entry.get("outputs", {})
	if not outputs_value is Dictionary:
		return {}
	var outputs: Dictionary = outputs_value
	var node_ids: Array = outputs.keys()
	node_ids.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
	for node_id: Variant in node_ids:
		var artifact: Dictionary = _find_artifact_descriptor(outputs[node_id], 0)
		if not artifact.is_empty():
			artifact["node_id"] = str(node_id)
			return artifact
	return {}


## Validates a local destination without touching the filesystem.
func validate_destination_path(destination_path: String) -> String:
	if destination_path.is_empty():
		return "Artifact destination path is required"
	if destination_path.length() > MAX_PATH_LENGTH:
		return "Artifact destination path exceeds %d characters" % MAX_PATH_LENGTH
	if not destination_path.begins_with("res://") and not destination_path.begins_with("user://"):
		return "Artifact destination must stay inside res:// or user://"
	var extension: String = destination_path.get_extension().to_lower()
	if extension not in SUPPORTED_ARTIFACT_EXTENSIONS:
		return "Unsupported artifact destination extension: " + extension
	var scheme_root: String = "res://" if destination_path.begins_with("res://") else "user://"
	var root_path: String = ProjectSettings.globalize_path(scheme_root).simplify_path()
	var resolved_path: String = ProjectSettings.globalize_path(destination_path).simplify_path()
	var root_prefix: String = root_path if root_path.ends_with("/") else root_path + "/"
	if resolved_path.to_lower() != root_path.to_lower() \
			and not resolved_path.to_lower().begins_with(root_prefix.to_lower()):
		return "Artifact destination escapes its Godot data root"
	if FileAccess.file_exists(destination_path):
		return "Artifact destination already exists: " + destination_path
	return ""


## Performs lightweight format validation before any downloaded bytes are
## written. Full parsing remains the responsibility of FoveaSplat3D.
func validate_artifact_bytes(filename: String, data: PackedByteArray) -> String:
	var extension: String = filename.get_extension().to_lower()
	if extension not in SUPPORTED_ARTIFACT_EXTENSIONS:
		return "Unsupported ComfyUI artifact extension: " + extension
	if data.is_empty():
		return "ComfyUI artifact is empty"
	match extension:
		"fovea":
			if data.size() < 8 or data.slice(0, 8).get_string_from_ascii() != "FOVEA_3D":
				return "Invalid .fovea magic header"
		"splat":
			if data.size() % SPLAT_STRIDE != 0:
				return ".splat artifact size is not a multiple of %d bytes" % SPLAT_STRIDE
		"ply":
			var probe_size: int = mini(data.size(), 65536)
			var header_probe: String = data.slice(0, probe_size).get_string_from_ascii()
			if not header_probe.begins_with("ply\n") and not header_probe.begins_with("ply\r\n"):
				return "Invalid .ply header"
			if header_probe.find("end_header") < 0:
				return ".ply end_header marker was not found in the first 64 KiB"
	return ""


func _poll_splat_artifact(
		prompt_id: String,
		destination_path: String,
		target: FoveaSplat3D,
		callback: Callable,
		tree: SceneTree,
		attempt: int
) -> void:
	if attempt >= max_poll_attempts:
		_finish(callback, {"ok": false, "error": "Timed out waiting for the ComfyUI splat artifact"})
		return
	await tree.create_timer(poll_interval_seconds).timeout
	var poller := HTTPRequest.new()
	tree.root.add_child(poller)
	_active_http_requests.append(poller)
	poller.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
			_cleanup_request(poller)
			if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
				_poll_splat_artifact(prompt_id, destination_path, target, callback, tree, attempt + 1)
				return
			var response: Variant = JSON.parse_string(response_body.get_string_from_utf8())
			if not response is Dictionary or not (response as Dictionary).has(prompt_id):
				_poll_splat_artifact(prompt_id, destination_path, target, callback, tree, attempt + 1)
				return
			var entry_value: Variant = (response as Dictionary)[prompt_id]
			if not entry_value is Dictionary:
				_finish(callback, {"ok": false, "error": "ComfyUI history entry is invalid"})
				return
			var artifact: Dictionary = find_first_splat_artifact(entry_value)
			if artifact.is_empty():
				_finish(callback, {
					"ok": false,
					"error": "ComfyUI workflow completed without a supported splat artifact",
				})
				return
			_download_splat_artifact(artifact, destination_path, target, callback, tree)
	)
	var request_error: Error = poller.request(_endpoint("/history/" + prompt_id.uri_encode()))
	if request_error != OK:
		_cleanup_request(poller)
		_poll_splat_artifact(prompt_id, destination_path, target, callback, tree, attempt + 1)


func _download_splat_artifact(
		artifact: Dictionary,
		destination_path: String,
		target: FoveaSplat3D,
		callback: Callable,
		tree: SceneTree
) -> void:
	var filename: String = str(artifact.get("filename", ""))
	var artifact_extension: String = filename.get_extension().to_lower()
	if artifact_extension != destination_path.get_extension().to_lower():
		_finish(callback, {
			"ok": false,
			"error": "ComfyUI artifact and destination extensions do not match",
		})
		return
	var query: String = "?filename=" + filename.uri_encode()
	var subfolder: String = str(artifact.get("subfolder", ""))
	if not subfolder.is_empty():
		query += "&subfolder=" + subfolder.uri_encode()
	query += "&type=" + str(artifact.get("type", "output")).uri_encode()

	var downloader := HTTPRequest.new()
	tree.root.add_child(downloader)
	_active_http_requests.append(downloader)
	downloader.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
			_cleanup_request(downloader)
			if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
				_finish(callback, {
					"ok": false,
					"error": "ComfyUI artifact download failed (result %d, HTTP %d)" % [result, response_code],
				})
				return
			var artifact_error: String = validate_artifact_bytes(filename, response_body)
			if not artifact_error.is_empty():
				_finish(callback, {"ok": false, "error": artifact_error})
				return
			var destination_error: String = validate_destination_path(destination_path)
			if not destination_error.is_empty():
				_finish(callback, {"ok": false, "error": destination_error})
				return
			var directory_path: String = destination_path.get_base_dir()
			var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(directory_path)
			)
			if mkdir_error != OK:
				_finish(callback, {
					"ok": false,
					"error": "Could not create artifact directory (%d)" % mkdir_error,
				})
				return
			var output: FileAccess = FileAccess.open(destination_path, FileAccess.WRITE)
			if output == null:
				_finish(callback, {
					"ok": false,
					"error": "Could not open the artifact destination for writing",
				})
				return
			output.store_buffer(response_body)
			var write_error: Error = output.get_error()
			output.close()
			if write_error != OK:
				_finish(callback, {"ok": false, "error": "Could not write the ComfyUI artifact"})
				return
			if target != null:
				target.source_path = destination_path
			_finish(callback, {
				"ok": true,
				"path": destination_path,
				"artifact": artifact.duplicate(true),
			})
	)
	var request_error: Error = downloader.request(_endpoint("/view") + query)
	if request_error != OK:
		_cleanup_request(downloader)
		_finish(callback, {
			"ok": false,
			"error": "Could not start the ComfyUI artifact download (%d)" % request_error,
		})


func _find_artifact_descriptor(value: Variant, depth: int) -> Dictionary:
	if depth > MAX_ARTIFACT_SCAN_DEPTH:
		return {}
	if value is Dictionary:
		var dictionary: Dictionary = value
		var filename: String = str(dictionary.get("filename", ""))
		if filename.get_extension().to_lower() in SUPPORTED_ARTIFACT_EXTENSIONS:
			return {
				"filename": filename,
				"subfolder": str(dictionary.get("subfolder", "")),
				"type": str(dictionary.get("type", "output")),
			}
		var keys: Array = dictionary.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
		for key: Variant in keys:
			var nested: Dictionary = _find_artifact_descriptor(dictionary[key], depth + 1)
			if not nested.is_empty():
				return nested
	elif value is Array:
		for item: Variant in value:
			var nested: Dictionary = _find_artifact_descriptor(item, depth + 1)
			if not nested.is_empty():
				return nested
	return {}


func _multipart_image_body(image_bytes: PackedByteArray, filename: String, boundary: String) -> PackedByteArray:
	var header: String = "--%s\r\n" % boundary
	header += "Content-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n" % filename
	header += "Content-Type: image/png\r\n\r\n"
	var body := PackedByteArray()
	body.append_array(header.to_utf8_buffer())
	body.append_array(image_bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return body


func _scene_tree() -> SceneTree:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop as SceneTree
	return null


func _finish(callback: Callable, result: Dictionary) -> void:
	if callback.is_valid():
		callback.call(result)
	elif not bool(result.get("ok", false)):
		push_error("ComfyUISplatBridge: " + str(result.get("error", "Unknown error")))
