class_name FoveaHermesBridge
extends Node

## Reserved integration point for the Hermes/Blender bridge.
##
## Godot 4 does not provide the Godot 3 `WebSocketServer` API used by the
## original implementation. Keeping that code made the entire addon fail to
## parse. A real server requires a Godot-4-compatible transport and protocol
## implementation; until then this node fails explicitly instead of exposing a
## partially functional network endpoint.

signal bridge_unavailable(message: String)

@export var port: int = 8765
@export var sandbox_enabled: bool = true

func _ready() -> void:
	var message: String = "FoveaHermesBridge is unavailable: the Godot 3 WebSocketServer API is not supported by Godot 4."
	push_warning(message)
	bridge_unavailable.emit(message)
