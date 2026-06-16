@tool
extends EditorContextMenuPlugin

## FoveaContextMenuPlugin — Custom right-click menu for FoveaSplattable nodes in the Scene Tree.
## Registers actions: "Generate Splats Now", "Export to .fovea", "Open in StudioTo3D".

var plugin: EditorPlugin = null

func _init(p_plugin: EditorPlugin = null) -> void:
	plugin = p_plugin

func _popup_menu(paths: PackedStringArray) -> void:
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	var has_splattable := false
	for node in selected_nodes:
		if node is FoveaSplattable:
			has_splattable = true
			break
	
	if has_splattable:
		add_context_menu_item("Fovea: Generate Splats Now", _on_generate_splats)
		add_context_menu_item("Fovea: Export to .fovea", _on_export_to_fovea)
		add_context_menu_item("Fovea: Open in StudioTo3D", _on_open_in_studio)

func _on_generate_splats(paths: PackedStringArray) -> void:
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is FoveaSplattable:
			node.generate_splats_now()

func _on_export_to_fovea(paths: PackedStringArray) -> void:
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is FoveaSplattable:
			if not node.splat_file_path.is_empty():
				var default_dest = node.splat_file_path.get_basename() + ".fovea"
				node.export_to_fovea(default_dest)
			else:
				# Try procedurally generating first if empty
				node.generate_splats_now()
				if not node.loaded_splats.is_empty():
					var default_dest = "res://procedural_splats.fovea"
					node.export_to_fovea(default_dest)
				else:
					push_warning("Fovea: FoveaSplattable has no mesh to convert.")

func _on_open_in_studio(paths: PackedStringArray) -> void:
	if plugin and plugin.panel:
		var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
		for node in selected_nodes:
			if node is FoveaSplattable:
				if plugin.panel.has_method("set_session_path_from_splattable"):
					plugin.panel.set_session_path_from_splattable(node)
					break
		plugin.panel.grab_focus()
		print("Fovea: Focused StudioTo3D Dock Panel and loaded session.")
