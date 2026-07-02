@tool
extends "res://addons/foveacore/scripts/editor/fovea_delta_painter_plugin.gd"
## Registration wrapper for the Delta Splat Painter.
##
## The painter's logic lives in
## res://addons/foveacore/scripts/editor/fovea_delta_painter_plugin.gd, but a
## script only receives _forward_3d_gui_input / _handles / toolbar callbacks when
## it is an *enabled* EditorPlugin. That file isn't registered on its own, so this
## thin subclass (referenced by plugin.cfg and listed in [editor_plugins]) is what
## actually activates it. No logic is duplicated — everything is inherited.
