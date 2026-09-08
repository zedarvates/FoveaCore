@tool
extends EditorPlugin
## FoveaLabs — experimental FoveaEngine modules.
##
## Registers the creation-dialog entries for experimental tools so the
## FoveaCore plugin stays lean and stable (see plans/PHASE0_FONDATION_TASKS.md, B3).
## All underlying scripts live in the foveacore addon and keep their global
## [code]class_name[/code]: disabling this plugin never breaks code access,
## it only removes the aliases below from the Create Node dialog.

# Table des types expérimentaux : [nom, classe de base, chemin du script, chemin de l'icône ou ""]
const CUSTOM_TYPES: Array[Array] = [
	["SplatBrush", "Node3D", "res://addons/foveacore/scripts/advanced/splat_brush_engine.gd", ""],
	["SplatVRBrush", "Node3D", "res://addons/foveacore/scripts/advanced/splat_vr_brush.gd", ""],
	["PhysicsProxy", "Node3D", "res://addons/foveacore/scripts/advanced/physics_proxy_generator.gd", ""],
	["NeuralStyle", "Resource", "res://addons/foveacore/scripts/advanced/neural_style_bridge.gd", ""],
	["FoveaSegmentation", "Resource", "res://addons/foveacore/scripts/advanced/fovea_segmentation_bridge.gd", ""],
	["SplatLightingAnimator", "Node", "res://addons/foveacore/scripts/advanced/splat_lighting_animator.gd", ""],
	["GPUNoiseGenerator", "Node", "res://addons/foveacore/scripts/materials/gpu_noise_generator.gd", ""],
	["FoveaClayDeformer", "Node3D", "res://addons/foveacore/scripts/advanced/fovea_clay_deformer.gd", ""],
	["FoveaSplatCloth", "Node3D", "res://addons/foveacore/scripts/advanced/fovea_splat_cloth.gd", ""],
	["SplatInteractionController", "Node", "res://addons/foveacore/scripts/advanced/splat_interaction_controller.gd", ""],
	["FoveaMultiplayerSync", "Node", "res://addons/foveacore/scripts/vr/fovea_multiplayer_sync.gd", ""],
	["SplatDecalTool", "Node3D", "res://addons/foveacore/scripts/advanced/splat_decal_tool.gd", ""],
	["Fovea4DPlayer", "Node", "res://addons/foveacore/scripts/advanced/fovea_4d_player.gd", ""],
]


func _enter_tree() -> void:
	for type_def in CUSTOM_TYPES:
		var icon: Texture2D = load(type_def[3]) if type_def[3] != "" else null
		add_custom_type(type_def[0], type_def[1], load(type_def[2]), icon)
	print("FoveaLabs plugin loaded — %d experimental types registered" % CUSTOM_TYPES.size())


func _exit_tree() -> void:
	for type_def in CUSTOM_TYPES:
		remove_custom_type(type_def[0])
	print("FoveaLabs unloaded")
