@tool
extends EditorPlugin

func _enter_tree():
	# Autoload
	add_autoload_singleton("FoveaCoreManager", "res://addons/foveacore/scripts/foveacore_manager.gd")
	add_autoload_singleton("ReconstructionManager", "res://addons/foveacore/scripts/reconstruction/reconstruction_manager.gd")
	add_autoload_singleton("EyeTrackingBridge", "res://addons/foveacore/scripts/advanced/gaze_tracker_linker.gd")
	add_autoload_singleton("StyleEngine", "res://addons/foveacore/scripts/materials/style_engine.gd")
	add_autoload_singleton("SplatGenerator", "res://addons/foveacore/scripts/splat_generator.gd")
	
	# Custom nodes
	add_custom_type("FoveaSplattable", "Node3D", preload("res://addons/foveacore/scripts/fovea_splattable.gd"), preload("res://addons/foveacore/icons/fovea_splattable.svg"))
	
	# GDExtension - charger seulement si disponible
	var gdextension_path = "res://addons/foveacore/gdextension/bin/foveacore.dll"
	if FileAccess.file_exists(gdextension_path):
		print("FoveaCore GDExtension loaded (native renderer)")
	else:
		print("FoveaCore running in GDScript-only mode (GDExtension not compiled)")
	
	# Advanced Components
	add_custom_type("SplatBrush", "Node3D", preload("res://addons/foveacore/scripts/advanced/splat_brush_engine.gd"), null)
	add_custom_type("PhysicsProxy", "Node3D", preload("res://addons/foveacore/scripts/advanced/physics_proxy_generator.gd"), null)
	add_custom_type("NeuralStyle", "Resource", preload("res://addons/foveacore/scripts/advanced/neural_style_bridge.gd"), null)
	add_custom_type("PlyLoader", "RefCounted", preload("res://addons/foveacore/scripts/ply_loader.gd"), null)
	
	print("FoveaCore plugin loaded with Advanced Features (Eye-tracking, Physics, Neural, PLY Loader)")
	
	# Add the StudioTo3D Panel
	var panel = preload("res://addons/foveacore/scripts/reconstruction/studio_to_3d_panel.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, panel)

func _exit_tree():
	remove_autoload_singleton("FoveaCoreManager")
	remove_autoload_singleton("ReconstructionManager")
	remove_autoload_singleton("EyeTrackingBridge")
	remove_autoload_singleton("StyleEngine")
	remove_autoload_singleton("SplatGenerator")
	remove_custom_type("FoveaSplattable")
	remove_custom_type("SplatBrush")
	remove_custom_type("PhysicsProxy")
	remove_custom_type("NeuralStyle")
	remove_custom_type("PlyLoader")
	print("FoveaCore unloaded")
