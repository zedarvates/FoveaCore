extends RefCounted
class_name SplatProcessorHelper

## SplatProcessorHelper - Helper for post-processing Gaussian Splats
## Handles automatic color-tagging (Leaves vs Trunk) and shape type detection.

## Classifies splats into semantic layers based on color (Leaves vs Trunk/Branches)
static func auto_tag_splats_by_color(splats: Array[GaussianSplat]) -> void:
	for splat in splats:
		var color := splat.color
		
		# Hue is in [0, 1] in Godot
		var hue := color.h
		var sat := color.s
		var val := color.v
		
		# 1. Detect Leaves (dominant green)
		# Green hue is typically around 120° (0.33). We check range [0.20, 0.45]
		# Saturation and value should be high enough to not match dark/grey colors
		if hue >= 0.20 and hue <= 0.45 and sat > 0.15 and val > 0.12:
			splat.layer_type = GaussianSplat.LayerType.LEAVES
			# Also set brush type for dynamic visual styling/logic
			splat.brush_type = GaussianSplat.BrushType.SPONGE
			
		# 2. Detect Trunk / Branches / Bark (browns and greys)
		# Brown/orange hue is typically around 30° (0.08). We check range [0.03, 0.18]
		# Greys are low saturation
		elif (hue >= 0.03 and hue <= 0.18 and sat > 0.08 and sat <= 0.85 and val > 0.05) or (sat < 0.12 and val > 0.08):
			splat.layer_type = GaussianSplat.LayerType.TRUNK
			splat.brush_type = GaussianSplat.BrushType.STONE
		else:
			splat.layer_type = GaussianSplat.LayerType.BASE
			splat.brush_type = GaussianSplat.BrushType.GAUSSIAN

## Assigns shape types to splats based on config and local geometry
## Shape encoding (stored in splat properties or palette indices):
## 0 = Quad (default), 1 = Triangle, 2 = Sphere/Circle, 3 = Auto
static func assign_shapes(splats: Array[GaussianSplat], shape_mode: String) -> void:
	for splat in splats:
		match shape_mode:
			"Quad":
				# Set brush_type to represent shape (0 = Quad/Stone, 1 = Sponge/Triangle, 2 = Circle/Gaussian)
				splat.brush_type = GaussianSplat.BrushType.STONE
			"Triangle":
				splat.brush_type = GaussianSplat.BrushType.SPONGE
			"Sphere":
				splat.brush_type = GaussianSplat.BrushType.GAUSSIAN
			"Auto", _:
				# Auto Mode: detect shape based on scale anisotropy
				var sx := splat.scale.x
				var sy := splat.scale.y
				var sz := splat.scale.z
				
				var max_s = max(sx, max(sy, sz))
				var min_s = min(sx, min(sy, sz))
				
				# Anisotropy ratio
				var ratio = max_s / max(min_s, 0.001)
				
				if ratio > 2.5:
					# Stretched / flat splat -> Triangle (good for leaves, grass, linear shapes)
					splat.brush_type = GaussianSplat.BrushType.SPONGE
				elif ratio > 1.5:
					# Moderately stretched -> Quad (standard)
					splat.brush_type = GaussianSplat.BrushType.STONE
				else:
					# Isotropic (almost equal size on all axes) -> Sphere/Circle
					splat.brush_type = GaussianSplat.BrushType.GAUSSIAN

## Decimates a splats array according to a density ratio (0.0 to 1.0)
static func decimate_splats(splats: Array[GaussianSplat], density_ratio: float) -> Array[GaussianSplat]:
	if density_ratio >= 0.99 or splats.is_empty():
		return splats
	var new_count = int(splats.size() * density_ratio)
	if new_count <= 0:
		new_count = 1
	var step = float(splats.size()) / new_count
	var decimated: Array[GaussianSplat] = []
	for i in range(new_count):
		var idx = int(i * step)
		if idx < splats.size():
			decimated.append(splats[idx])
	return decimated
