@tool
extends RefCounted
class_name FoveaSplatPaintTool

## FoveaSplatPaintTool - Editor interactive painting helper for Delta-Splat.

static func paint_splats(
	splattable: FoveaSplattable,
	brush_center_local: Vector3,
	radius: float,
	mode: String, # "color", "deform", "erase"
	color: Color,
	offset: Vector3
) -> void:
	if splattable == null or splattable.loaded_splats.is_empty():
		return

	# Calculate distance and apply modifications
	for i in range(splattable.loaded_splats.size()):
		var s: GaussianSplat = splattable.loaded_splats[i]
		var dist: float = s.position.distance_to(brush_center_local)
		if dist <= radius:
			match mode:
				"color":
					splattable.set_delta_color(i, color)
				"deform":
					splattable.set_delta_position(i, offset)
				"erase":
					splattable.delta_colors.erase(i)
					splattable.delta_positions.erase(i)
	
	# Force updates
	splattable.notify_property_list_changed()
