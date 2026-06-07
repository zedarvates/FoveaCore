@tool
extends EditorPlugin

# Instance du plugin d'exportation pour injecter les permissions Android
var export_plugin: FoveaAndroidExportPlugin = null

func _enter_tree():
	# Autoloads
	add_autoload_singleton("FoveaCoreManager", "res://addons/foveacore/scripts/foveacore_manager.gd")
	add_autoload_singleton("ReconstructionManager", "res://addons/foveacore/scripts/reconstruction/reconstruction_manager.gd")
	add_autoload_singleton("EyeTrackingBridge", "res://addons/foveacore/scripts/advanced/gaze_tracker_linker.gd")
	
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
	add_custom_type("SplatVRBrush", "Node3D", preload("res://addons/foveacore/scripts/advanced/splat_vr_brush.gd"), null)
	add_custom_type("PhysicsProxy", "Node3D", preload("res://addons/foveacore/scripts/advanced/physics_proxy_generator.gd"), null)
	add_custom_type("NeuralStyle", "Resource", preload("res://addons/foveacore/scripts/advanced/neural_style_bridge.gd"), null)
	add_custom_type("PLYLoader", "RefCounted", preload("res://addons/foveacore/scripts/reconstruction/ply_loader.gd"), null)
	add_custom_type("GPUCullerPipeline", "RefCounted", preload("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd"), null)
	add_custom_type("GPUNoiseGenerator", "Node", preload("res://addons/foveacore/scripts/materials/gpu_noise_generator.gd"), null)
	add_custom_type("StudioPreviewManager", "Node", preload("res://addons/foveacore/scripts/reconstruction/studio_preview_manager.gd"), null)
	add_custom_type("StudioRoiPainter", "AcceptDialog", preload("res://addons/foveacore/scripts/reconstruction/studio_roi_painter.gd"), null)
	add_custom_type("WorldMirrorCameraImporter", "Node", preload("res://addons/foveacore/scripts/reconstruction/worldmirror_camera_importer.gd"), null)
	add_custom_type("WorldMirrorDepthLoader", "Node", preload("res://addons/foveacore/scripts/reconstruction/worldmirror_depth_loader.gd"), null)
	
	# Sprint 4 — Clay Deformer & Physics Tools
	add_custom_type("FoveaClayDeformer", "Node3D",    preload("res://addons/foveacore/scripts/advanced/fovea_clay_deformer.gd"),  null)
	add_custom_type("FoveaVoxelizer",    "RefCounted", preload("res://addons/foveacore/scripts/advanced/fovea_voxelizer.gd"),     null)
	add_custom_type("FoveaSplatCleaner", "RefCounted", preload("res://addons/foveacore/scripts/advanced/fovea_splat_cleaner.gd"), null)

	# Phase 3 — Global Splat Instancing
	add_custom_type("FoveaInstancedSplatRenderer", "MultiMeshInstance3D", preload("res://addons/foveacore/scripts/advanced/fovea_instanced_splat_renderer.gd"), null)
	add_custom_type("FoveaInstancedCuller", "RefCounted", preload("res://addons/foveacore/scripts/advanced/fovea_instanced_culler.gd"), null)

	# Manager Sub-Systems (refactoring God Object)
	add_custom_type("FoveaVRSubsystem",       "Node", preload("res://addons/foveacore/scripts/fovea_vr_subsystem.gd"),       null)
	add_custom_type("FoveaFoveatedSubsystem", "Node", preload("res://addons/foveacore/scripts/fovea_foveated_subsystem.gd"), null)
	add_custom_type("FoveaSplatSubsystem",    "Node", preload("res://addons/foveacore/scripts/fovea_splat_subsystem.gd"),    null)

	# Enregistrement du plugin d'exportation pour injecter les permissions Android
	export_plugin = FoveaAndroidExportPlugin.new()
	add_export_plugin(export_plugin)

	print("FoveaCore plugin loaded — Eye-tracking, Physics, Neural, PLY Loader, Clay Deformer (Sprint 4)")
	
	# Add the StudioTo3D Panel
	var panel = preload("res://addons/foveacore/scripts/reconstruction/studio_to_3d_panel.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, panel)

func _exit_tree():
	remove_autoload_singleton("FoveaCoreManager")
	remove_autoload_singleton("ReconstructionManager")
	remove_autoload_singleton("EyeTrackingBridge")
	
	remove_custom_type("FoveaSplattable")
	remove_custom_type("SplatBrush")
	remove_custom_type("SplatVRBrush")
	remove_custom_type("PhysicsProxy")
	remove_custom_type("NeuralStyle")
	remove_custom_type("PLYLoader")
	remove_custom_type("GPUCullerPipeline")
	remove_custom_type("GPUNoiseGenerator")
	remove_custom_type("StudioPreviewManager")
	remove_custom_type("StudioRoiPainter")
	remove_custom_type("WorldMirrorCameraImporter")
	remove_custom_type("WorldMirrorDepthLoader")
	remove_custom_type("FoveaClayDeformer")
	remove_custom_type("FoveaVoxelizer")
	remove_custom_type("FoveaSplatCleaner")
	remove_custom_type("FoveaInstancedSplatRenderer")
	remove_custom_type("FoveaInstancedCuller")
	remove_custom_type("FoveaVRSubsystem")
	remove_custom_type("FoveaFoveatedSubsystem")
	remove_custom_type("FoveaSplatSubsystem")
	
	# Retrait du plugin d'exportation
	if export_plugin:
		remove_export_plugin(export_plugin)
		export_plugin = null
		
	print("FoveaCore unloaded")

# Sous-classe interne gérant l'exportation des permissions d'eye tracking sur Android (Quest Pro / Android XR)
class FoveaAndroidExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "FoveaAndroidExportPlugin"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform.get_name() == "Android"

	func _get_android_manifest_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
		return "<uses-permission android:name=\"android.permission.EYE_TRACKING_FINE\" />\n<uses-permission android:name=\"com.oculus.permission.EYE_TRACKING\" />"
