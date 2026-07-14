@tool
extends EditorPlugin

# Instance du plugin d'exportation pour injecter les permissions Android
var export_plugin: FoveaAndroidExportPlugin = null
var style_inspector_plugin: EditorInspectorPlugin = null
var splattable_inspector_plugin: EditorInspectorPlugin = null
var splattable_gizmo_plugin: EditorNode3DGizmoPlugin = null

# "Add FoveaSplat3D…" — always-visible viewport action to create a splat node
# from a file (reliable alternative to viewport drag-and-drop, see PHASE0 E1).
var add_splat_button: Button = null
var add_splat_dialog: EditorFileDialog = null

const FoveaSplat3DScript = preload("res://addons/foveacore/scripts/fovea_splat_3d.gd")

const FoveaAssetFormatLoaderScript = preload("res://addons/foveacore/scripts/fovea_asset_loader.gd")
const FoveaAssetFormatSaverScript = preload("res://addons/foveacore/scripts/fovea_asset_saver.gd")

# Table des autoloads : [nom, chemin du script]
const AUTOLOADS: Array[Array] = [
	["FoveaCoreManager", "res://addons/foveacore/scripts/foveacore_manager.gd"],
	["ReconstructionManager", "res://addons/foveacore/scripts/reconstruction/reconstruction_manager.gd"],
	["EyeTrackingBridge", "res://addons/foveacore/scripts/advanced/gaze_tracker_linker.gd"],
]

# Table des types personnalisés : [nom, classe de base, chemin du script, chemin de l'icône ou ""]
# L'enregistrement et le retrait parcourent la même table : impossible d'oublier un cleanup.
#
# Périmètre volontairement minimal (voir plans/PHASE0_FONDATION_TASKS.md, B3) :
# - Les outils expérimentaux (brushes, cloth, decals, multiplayer, neural...) sont
#   enregistrés par le plugin séparé addons/fovea_labs.
# - Les utilitaires internes (PLYLoader, GPUCullerPipeline, FoveaVoxelizer,
#   sous-systèmes du manager, etc.) ont tous un class_name global : ils restent
#   accessibles partout en code sans add_custom_type.
const CUSTOM_TYPES: Array[Array] = [
	# API publique v1 — le nœud principal (voir plans/PHASE0_FONDATION_TASKS.md, A1)
	["FoveaSplat3D", "Node3D", "res://addons/foveacore/scripts/fovea_splat_3d.gd", "res://addons/foveacore/icons/fovea_splattable.svg"],
	["FoveaAsset", "Resource", "res://addons/foveacore/scripts/fovea_asset.gd", ""],
	["FoveaSplattable", "Node3D", "res://addons/foveacore/scripts/fovea_splattable.gd", "res://addons/foveacore/icons/fovea_splattable.svg"],
]

# Custom Resource Format Loader and Saver for .fovea binary format
var format_loader: ResourceFormatLoader = null
var format_saver: ResourceFormatSaver = null

# StudioTo3D UI Panel Dock control
var panel: Control = null

# Active FoveaSplattable node selected in editor and its viewport menu button
var selected_splattable: FoveaSplattable = null
var fovea_menu: MenuButton = null
var context_menu_plugin: EditorContextMenuPlugin = null

func _enter_tree():
	# Register .fovea custom resource format loader and saver
	format_loader = FoveaAssetFormatLoaderScript.new()
	format_saver = FoveaAssetFormatSaverScript.new()
	ResourceLoader.add_resource_format_loader(format_loader)
	ResourceSaver.add_resource_format_saver(format_saver)

	# Autoloads
	for autoload in AUTOLOADS:
		add_autoload_singleton(autoload[0], autoload[1])

	# Custom types (table-driven, see CUSTOM_TYPES)
	for type_def in CUSTOM_TYPES:
		var icon: Texture2D = load(type_def[3]) if type_def[3] != "" else null
		add_custom_type(type_def[0], type_def[1], load(type_def[2]), icon)

	# GDExtension - charger seulement si disponible
	var gdextension_path = "res://addons/foveacore/gdextension/bin/foveacore.dll"
	if FileAccess.file_exists(gdextension_path):
		print("FoveaCore GDExtension loaded (native renderer)")
	else:
		print("FoveaCore running in GDScript-only mode (GDExtension not compiled)")

	# Enregistrement du plugin d'exportation pour injecter les permissions Android
	export_plugin = FoveaAndroidExportPlugin.new()
	add_export_plugin(export_plugin)

	# Inspector Plugin Setup
	var inspector_plugin_script = load("res://addons/foveacore/scripts/editor/fovea_style_inspector_plugin.gd")
	if inspector_plugin_script:
		style_inspector_plugin = inspector_plugin_script.new()
		add_inspector_plugin(style_inspector_plugin)

	# Action buttons for FoveaSplattable / FoveaSplat3D (remplace les checkboxes trigger_*)
	var splattable_inspector_script = load("res://addons/foveacore/scripts/editor/fovea_splattable_inspector_plugin.gd")
	if splattable_inspector_script:
		splattable_inspector_plugin = splattable_inspector_script.new()
		add_inspector_plugin(splattable_inspector_plugin)

	# Gizmo Plugin Setup
	var gizmo_plugin_script = load("res://addons/foveacore/scripts/editor/fovea_splattable_gizmo_plugin.gd")
	if gizmo_plugin_script:
		splattable_gizmo_plugin = gizmo_plugin_script.new()
		add_node_3d_gizmo_plugin(splattable_gizmo_plugin)

	# Context Menu Plugin Setup
	context_menu_plugin = preload("res://addons/foveacore/scripts/editor/fovea_context_menu_plugin.gd").new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, context_menu_plugin)

	print("FoveaCore plugin loaded — splat rendering, foveated VR, StudioTo3D (experimental tools: enable the FoveaLabs plugin)")

	# Add the StudioTo3D Panel.
	# Note : plus de wizard modal à l'activation — si les outils externes ne sont pas
	# configurés, le panneau StudioTo3D affiche une bannière non bloquante.
	panel = preload("res://addons/foveacore/scripts/reconstruction/studio_to_3d_panel.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, panel)

	# VIEWPORT TOOLBAR MENU SETUP
	fovea_menu = MenuButton.new()
	fovea_menu.text = "FoveaSplattable"
	fovea_menu.flat = true
	fovea_menu.visible = false

	var popup = fovea_menu.get_popup()
	popup.add_item("Reload / Generate Splats", 0)
	popup.add_item("Convert PLY to .fovea", 1)
	popup.add_item("Generate physical collision shape", 2)
	popup.add_separator()
	popup.add_item("Open in StudioTo3D Panel", 3)

	popup.id_pressed.connect(_on_menu_item_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, fovea_menu)

	# Always-visible "Add FoveaSplat3D…" button (file picker → new node).
	add_splat_button = Button.new()
	add_splat_button.text = "＋ FoveaSplat3D"
	add_splat_button.flat = true
	add_splat_button.tooltip_text = "Create a FoveaSplat3D in the current scene from a .ply / .fovea / .spz file"
	add_splat_button.pressed.connect(_on_add_splat_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, add_splat_button)

	add_splat_dialog = EditorFileDialog.new()
	add_splat_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	add_splat_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	add_splat_dialog.clear_filters()
	add_splat_dialog.add_filter("*.fovea", "Fovea asset")
	add_splat_dialog.add_filter("*.ply", "Gaussian Splatting PLY")
	add_splat_dialog.add_filter("*.spz", "SPZ splat")
	add_splat_dialog.title = "Select a splat file"
	add_splat_dialog.file_selected.connect(_on_splat_file_selected)
	EditorInterface.get_base_control().add_child(add_splat_dialog)

func _exit_tree():
	if panel:
		remove_control_from_docks(panel)
		panel.queue_free()
		panel = null

	# Godot unregisters script-backed format handlers before this callback during
	# editor shutdown. Removing them again triggers an engine error; dropping our
	# references is sufficient and also keeps plugin reloads safe.
	format_loader = null
	format_saver = null

	for type_def in CUSTOM_TYPES:
		remove_custom_type(type_def[0])

	for autoload in AUTOLOADS:
		remove_autoload_singleton(autoload[0])

	# Retrait du plugin d'exportation
	if export_plugin:
		remove_export_plugin(export_plugin)
		export_plugin = null

	# Clean up Inspector Plugins
	if style_inspector_plugin:
		remove_inspector_plugin(style_inspector_plugin)
		style_inspector_plugin = null
	if splattable_inspector_plugin:
		remove_inspector_plugin(splattable_inspector_plugin)
		splattable_inspector_plugin = null

	# Clean up Gizmo Plugin
	if splattable_gizmo_plugin:
		remove_node_3d_gizmo_plugin(splattable_gizmo_plugin)
		splattable_gizmo_plugin = null

	# Clean up Viewport MenuButton
	if fovea_menu:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, fovea_menu)
		fovea_menu.queue_free()
		fovea_menu = null

	# Clean up "Add FoveaSplat3D…" button + dialog
	if add_splat_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, add_splat_button)
		add_splat_button.queue_free()
		add_splat_button = null
	if add_splat_dialog:
		add_splat_dialog.queue_free()
		add_splat_dialog = null

	# Clean up Context Menu Plugin
	if context_menu_plugin:
		remove_context_menu_plugin(context_menu_plugin)
		context_menu_plugin = null

	print("FoveaCore unloaded")


func _on_add_splat_pressed() -> void:
	if add_splat_dialog:
		add_splat_dialog.popup_centered_ratio(0.6)


func _on_splat_file_selected(path: String) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("FoveaPlugin: Open or create a scene first, then add a FoveaSplat3D.")
		return

	# Parent to the current selection if it's a Node3D, else to the scene root.
	var parent: Node = root
	var sel: Array = EditorInterface.get_selection().get_selected_nodes()
	if sel.size() == 1 and sel[0] is Node3D:
		parent = sel[0]

	var splat: Node3D = FoveaSplat3DScript.new()
	splat.name = path.get_file().get_basename().to_pascal_case() + "Splat"
	splat.set("source_path", path)

	# Register with the editor's undo/redo so creation is reversible.
	var ur: EditorUndoRedoManager = get_undo_redo()
	ur.create_action("Add FoveaSplat3D")
	ur.add_do_method(parent, "add_child", splat)
	ur.add_do_method(splat, "set_owner", root)
	ur.add_do_reference(splat)
	ur.add_undo_method(parent, "remove_child", splat)
	ur.commit_action()

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(splat)
	print("FoveaPlugin: Added FoveaSplat3D '%s' from %s" % [splat.name, path])

func _handles(object: Object) -> bool:
	return object is FoveaSplattable

func _edit(object: Object) -> void:
	selected_splattable = object as FoveaSplattable

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if selected_splattable == null or not is_instance_valid(selected_splattable):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not selected_splattable.get_meta("paint_mode", false):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
		
	# Handle mouse inputs
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_paint_at_mouse(viewport_camera, mouse_event.position)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_paint_at_mouse(viewport_camera, motion_event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
			
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _paint_at_mouse(camera: Camera3D, mouse_pos: Vector2) -> void:
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	
	var local_origin := selected_splattable.to_local(origin)
	var local_dir := selected_splattable.to_local(origin + dir * 100.0) - local_origin
	local_dir = local_dir.normalized()
	
	# Find closest splat to the projected ray
	var closest_idx := -1
	var min_dist := 999999.0
	var hit_pos := Vector3.ZERO
	
	var brush_radius: float = selected_splattable.get_meta("paint_brush_radius", 0.5)
	
	for i in range(selected_splattable.loaded_splats.size()):
		var s := selected_splattable.loaded_splats[i]
		var to_s := s.position - local_origin
		var projection := to_s.dot(local_dir)
		if projection < 0.0:
			continue
		var proj_point := local_origin + local_dir * projection
		var dist := s.position.distance_to(proj_point)
		if dist < min_dist and dist < brush_radius:
			min_dist = dist
			closest_idx = i
			hit_pos = s.position
			
	if closest_idx != -1:
		var brush_mode_idx: int = selected_splattable.get_meta("paint_brush_mode", 0)
		var mode_str := "color"
		if brush_mode_idx == 1:
			mode_str = "deform"
		elif brush_mode_idx == 2:
			mode_str = "erase"
			
		var color: Color = selected_splattable.get_meta("paint_brush_color", Color.RED)
		var deform_offset := local_dir * 0.1 # push splats slightly along view ray
		
		var paint_tool := load("res://addons/foveacore/scripts/editor/fovea_splat_paint_tool.gd")
		if paint_tool:
			paint_tool.paint_splats(selected_splattable, hit_pos, brush_radius, mode_str, color, deform_offset)

func _make_visible(visible: bool) -> void:
	if fovea_menu:
		fovea_menu.visible = visible

func _on_menu_item_pressed(id: int) -> void:
	if selected_splattable == null or not is_instance_valid(selected_splattable):
		return

	match id:
		0: # Reload / Generate Splats
			if not selected_splattable.splat_file_path.is_empty():
				selected_splattable._load_splats_from_ply()
				print("FoveaPlugin: Reloaded splats from PLY path: ", selected_splattable.splat_file_path)
			else:
				print("FoveaPlugin: Cannot reload: splat file path is empty.")
		1: # Convert PLY to .fovea
			if not selected_splattable.splat_file_path.is_empty():
				var default_dest = selected_splattable.splat_file_path.get_basename() + ".fovea"
				var ok = selected_splattable.export_to_fovea(default_dest)
				if ok:
					print("FoveaPlugin: Successfully converted to: ", default_dest)
					selected_splattable.splat_file_path = default_dest
				else:
					push_error("FoveaPlugin: Conversion failed.")
			else:
				push_error("FoveaPlugin: Cannot convert: No splat file path set.")
		2: # Generate physical collision shape
			if selected_splattable.splat_file_path.ends_with(".fovea"):
				selected_splattable._generate_collision_shape()
				print("FoveaPlugin: Generated physical collision shape.")
			else:
				push_error("FoveaPlugin: Collision shape generation requires a .fovea asset format.")
		3: # Open in StudioTo3D Panel
			if panel:
				if panel.has_method("set_session_path_from_splattable"):
					panel.set_session_path_from_splattable(selected_splattable)
				else:
					print("FoveaPlugin: Panel does not support loading splattable paths.")

# Sous-classe interne gérant l'exportation des permissions d'eye tracking sur Android (Quest Pro / Android XR)
class FoveaAndroidExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "FoveaAndroidExportPlugin"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform.get_name() == "Android"

	func _get_android_manifest_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
		return "<uses-permission android:name=\"android.permission.EYE_TRACKING_FINE\" />\n<uses-permission android:name=\"com.oculus.permission.EYE_TRACKING\" />"
