class_name FoveaFlowPaintTool
extends Node3D
@export var brush_radius: float = 0.5
@export var brush_strength: float = 1.0
@export var flow_texture_resolution: int = 32
var _flow_texture: Dictionary = {}
func _init() -> void: _clear_texture()
func _clear_texture() -> void:
	_flow_texture.clear()
	for x in flow_texture_resolution:
		for y in flow_texture_resolution:
			for z in flow_texture_resolution:
				_flow_texture["%d,%d,%d" % [x, y, z]] = Vector3.ZERO
func paint_stroke(origin: Vector3, direction: Vector3, radius: float = -1.0, strength: float = -1.0) -> void:
	if radius < 0: radius = brush_radius
	if strength < 0: strength = brush_strength
	var bounds = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var g = flow_texture_resolution
	for x in range(g):
		for y in range(g):
			for z in range(g):
				var wp = bounds.position + bounds.size * Vector3(float(x)/g, float(y)/g, float(z)/g)
				if origin.distance_squared_to(wp) <= radius * radius:
					var key = "%d,%d,%d" % [x, y, z]
					_flow_texture[key] = _flow_texture.get(key, Vector3.ZERO).lerp(direction.normalized() * strength, 0.5)
func get_flow_at(world_pos: Vector3) -> Vector3:
	var bounds = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var frac = (world_pos - bounds.position) / max(bounds.size, Vector3.ONE * 0.001)
	var g = flow_texture_resolution
	return _flow_texture.get("%d,%d,%d" % [int(frac.x*(g-1)), int(frac.y*(g-1)), int(frac.z*(g-1))], Vector3.ZERO)
