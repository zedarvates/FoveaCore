@tool
extends RefCounted
class_name FoveaCliBridge

## Optional, provider-neutral automation contract for local Godot control tools.
##
## The bridge never writes scene files, starts network listeners, or invokes an
## LLM. Callers remain responsible for authentication, mutation approval, scene
## persistence, and user-visible diffs.

const CONTRACT_VERSION := 1
const SUPPORTED_EXTENSIONS := ["fovea", "ply", "splat"]
const QUALITY_PRESET_NAMES := ["auto", "performance", "balanced", "cinematic"]
const MAX_NODE_PATH_LENGTH := 1024
const MAX_SOURCE_PATH_LENGTH := 1024
const MAX_NODE_NAME_LENGTH := 128


func contract() -> Dictionary:
	return {
		"name": "foveacore-cli",
		"version": CONTRACT_VERSION,
		"public_node": "FoveaSplat3D",
		"supported_extensions": SUPPORTED_EXTENSIONS.duplicate(),
		"operations": ["status", "validate", "add_splat"],
		"writes_files": false,
		"starts_network_listener": false,
	}


func status(tree: SceneTree, max_nodes: int) -> Dictionary:
	var limit_error: String = _validate_limit(max_nodes)
	if not limit_error.is_empty():
		return {"ok": false, "error": limit_error}

	var scene_root: Node = tree.current_scene
	if scene_root == null:
		return {
			"ok": true,
			"data": {
				"available": true,
				"contract": contract(),
				"scene_present": false,
				"scene_path": "",
				"splat_count": 0,
				"splats": [],
				"complete": true,
				"visited_nodes": 0,
				"max_nodes": max_nodes,
			},
		}

	var scan: Dictionary = _scan_scene(scene_root, max_nodes)
	return {
		"ok": true,
		"data": {
			"available": true,
			"contract": contract(),
			"scene_present": true,
			"scene_path": str(scene_root.get_path()),
			"splat_count": (scan["splats"] as Array).size(),
			"splats": scan["splats"],
			"complete": not bool(scan["truncated"]),
			"visited_nodes": scan["visited_nodes"],
			"max_nodes": max_nodes,
		},
	}


func validate(tree: SceneTree, max_nodes: int) -> Dictionary:
	var status_result: Dictionary = status(tree, max_nodes)
	if not bool(status_result.get("ok", false)):
		return status_result

	var status_data: Dictionary = status_result["data"]
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	if not bool(status_data["scene_present"]):
		errors.append({
			"rule": "fovea_scene_missing",
			"message": "No current scene is available for Fovea validation",
		})

	for item_value: Variant in status_data["splats"]:
		var item: Dictionary = item_value as Dictionary
		var source_path: String = str(item.get("source_path", ""))
		var path: String = str(item.get("path", ""))
		var source_error: String = _validate_source_path(source_path, true)
		if not source_error.is_empty():
			errors.append({
				"rule": "fovea_source_invalid",
				"path": path,
				"source_path": source_path,
				"message": source_error,
			})
		elif int(item.get("loaded_splat_count", 0)) < 1:
			errors.append({
				"rule": "fovea_source_not_loaded",
				"path": path,
				"source_path": source_path,
				"message": "Fovea source did not load any splats",
			})
		if bool(item.get("generate_collisions", false)) \
				and source_path.get_extension().to_lower() != "fovea":
			errors.append({
				"rule": "fovea_collision_requires_native_asset",
				"path": path,
				"source_path": source_path,
				"message": "Collision generation requires a native .fovea source",
			})

	if not bool(status_data["complete"]):
		errors.append({
			"rule": "fovea_validation_budget_exceeded",
			"message": "Fovea validation stopped after %d nodes" % max_nodes,
		})

	return {
		"ok": true,
		"data": {
			"available": true,
			"contract": contract(),
			"valid": errors.is_empty(),
			"complete": bool(status_data["complete"]),
			"splat_count": status_data["splat_count"],
			"visited_nodes": status_data["visited_nodes"],
			"max_nodes": max_nodes,
			"error_count": errors.size(),
			"warning_count": warnings.size(),
			"errors": errors,
			"warnings": warnings,
		},
	}


func add_splat(tree: SceneTree, params: Dictionary) -> Dictionary:
	var scene_root: Node = tree.current_scene
	if scene_root == null:
		return {"ok": false, "error": "No current scene"}

	var parent_path: String = str(params.get("parent", ""))
	var source_path: String = str(params.get("source_path", ""))
	var requested_name: String = str(params.get("name", ""))
	var quality_name: String = str(params.get("quality", "auto")).to_lower()
	var opacity_value: Variant = params.get("opacity", 1.0)
	var collisions_value: Variant = params.get("generate_collisions", false)
	var static_value: Variant = params.get("is_static", true)

	if parent_path.is_empty():
		return {"ok": false, "error": "Missing 'parent' parameter"}
	if parent_path.length() > MAX_NODE_PATH_LENGTH:
		return {"ok": false, "error": "Parent path exceeds %d characters" % MAX_NODE_PATH_LENGTH}
	var parent: Node = tree.root.get_node_or_null(parent_path)
	if parent == null:
		return {"ok": false, "error": "Parent not found: " + parent_path}
	if parent != scene_root and not scene_root.is_ancestor_of(parent):
		return {"ok": false, "error": "Parent must belong to the current scene"}

	var source_error: String = _validate_source_path(source_path, true)
	if not source_error.is_empty():
		return {"ok": false, "error": source_error}
	if not quality_name in QUALITY_PRESET_NAMES:
		return {
			"ok": false,
			"error": "Quality must be one of: auto, performance, balanced, cinematic",
		}
	if not (opacity_value is int or opacity_value is float):
		return {"ok": false, "error": "Opacity must be a number between 0 and 1"}
	var opacity: float = float(opacity_value)
	if is_nan(opacity) or is_inf(opacity) or opacity < 0.0 or opacity > 1.0:
		return {"ok": false, "error": "Opacity must be a finite number between 0 and 1"}
	if not collisions_value is bool:
		return {"ok": false, "error": "generate_collisions must be a boolean"}
	if not static_value is bool:
		return {"ok": false, "error": "is_static must be a boolean"}
	if bool(collisions_value) and source_path.get_extension().to_lower() != "fovea":
		return {"ok": false, "error": "Collision generation requires a native .fovea source"}

	var node_name: String = requested_name
	if node_name.is_empty():
		node_name = source_path.get_file().get_basename().to_pascal_case() + "Splat"
	if node_name.length() > MAX_NODE_NAME_LENGTH:
		return {"ok": false, "error": "Fovea node name exceeds %d characters" % MAX_NODE_NAME_LENGTH}
	if node_name.is_empty() or node_name != node_name.validate_node_name():
		return {"ok": false, "error": "Invalid Fovea node name: " + node_name}
	if parent.has_node(NodePath(node_name)):
		return {"ok": false, "error": "A child named '%s' already exists" % node_name}

	var splat: FoveaSplat3D = FoveaSplat3D.new()
	splat.name = node_name
	splat.source_path = source_path
	splat.quality_preset = _quality_preset_from_name(quality_name)
	splat.opacity = opacity
	splat.generate_collisions = bool(collisions_value)
	splat.is_static = bool(static_value)
	parent.add_child(splat)
	splat.owner = scene_root
	var loaded_splat_count: int = _loaded_splat_count(splat)
	if loaded_splat_count < 1:
		parent.remove_child(splat)
		splat.queue_free()
		return {"ok": false, "error": "Fovea source did not load any splats: " + source_path}

	return {
		"ok": true,
		"data": {
			"contract_version": CONTRACT_VERSION,
			"path": str(splat.get_path()),
			"name": str(splat.name),
			"type": "FoveaSplat3D",
			"source_path": splat.source_path,
			"quality": quality_name,
			"opacity": splat.opacity,
			"generate_collisions": splat.generate_collisions,
			"is_static": splat.is_static,
			"loaded_splat_count": loaded_splat_count,
			"persisted": false,
		},
	}


func _scan_scene(scene_root: Node, max_nodes: int) -> Dictionary:
	var splats: Array[Dictionary] = []
	var stack: Array[Node] = [scene_root]
	var visited_nodes := 0
	var truncated := false
	while not stack.is_empty():
		if visited_nodes >= max_nodes:
			truncated = true
			break
		var node: Node = stack.pop_back()
		visited_nodes += 1
		if node is FoveaSplat3D:
			var splat: FoveaSplat3D = node as FoveaSplat3D
			splats.append({
				"path": str(splat.get_path()),
				"name": str(splat.name),
				"source_path": splat.source_path,
				"source_exists": FileAccess.file_exists(splat.source_path),
				"loaded_splat_count": _loaded_splat_count(splat),
				"quality_preset": int(splat.quality_preset),
				"opacity": splat.opacity,
				"generate_collisions": splat.generate_collisions,
				"is_static": splat.is_static,
			})
		for child_index: int in range(node.get_child_count() - 1, -1, -1):
			stack.append(node.get_child(child_index))
	return {
		"splats": splats,
		"visited_nodes": visited_nodes,
		"truncated": truncated,
	}


func _validate_limit(max_nodes: int) -> String:
	if max_nodes < 1 or max_nodes > 4096:
		return "max_nodes must be between 1 and 4096"
	return ""


func _validate_source_path(source_path: String, require_existing: bool) -> String:
	if source_path.is_empty():
		return "Fovea source path is required"
	if not source_path.begins_with("res://"):
		return "Fovea source path must stay inside res://"
	if source_path.length() > MAX_SOURCE_PATH_LENGTH:
		return "Fovea source path exceeds %d characters" % MAX_SOURCE_PATH_LENGTH
	var project_root: String = ProjectSettings.globalize_path("res://").simplify_path()
	var resolved: String = ProjectSettings.globalize_path(source_path).simplify_path()
	var root_prefix: String = project_root if project_root.ends_with("/") else project_root + "/"
	if resolved.to_lower() != project_root.to_lower() \
			and not resolved.to_lower().begins_with(root_prefix.to_lower()):
		return "Fovea source path must stay inside res://"
	var extension: String = source_path.get_extension().to_lower()
	if extension not in SUPPORTED_EXTENSIONS:
		return "Unsupported Fovea source extension: " + extension
	if require_existing and not FileAccess.file_exists(source_path):
		return "Fovea source file not found: " + source_path
	return ""


func _quality_preset_from_name(quality_name: String) -> int:
	match quality_name:
		"performance":
			return FoveaSplat3D.QualityPreset.PERFORMANCE
		"balanced":
			return FoveaSplat3D.QualityPreset.BALANCED
		"cinematic":
			return FoveaSplat3D.QualityPreset.CINEMATIC
		_:
			return FoveaSplat3D.QualityPreset.AUTO


func _loaded_splat_count(splat: FoveaSplat3D) -> int:
	var advanced: FoveaSplattable = splat.get_advanced()
	if advanced == null:
		return 0
	return advanced.loaded_splats.size()
