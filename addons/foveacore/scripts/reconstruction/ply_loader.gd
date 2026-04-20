extends RefCounted
class_name PLYLoader

## PLYLoader — Specializes in loading Gaussian Splatting .ply files
## Parses binary formats containing positions, opacities, scales, and rotations.

const GaussianSplat = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

static func load_gaussians_from_ply(path: String) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []

	if not FileAccess.file_exists(path):
		push_error("PLYLoader: File not found: " + path)
		return splats

	var file = FileAccess.open(path, FileAccess.READ)

	# Parse Header
	var line = file.get_line()
	if line != "ply":
		push_error("PLYLoader: Not a valid PLY file.")
		return splats

	var element_count = 0
	var properties: Array[String] = []

	while line != "end_header":
		line = file.get_line()
		if line.begins_with("element vertex"):
			element_count = line.split(" ")[2].to_int()
		elif line.begins_with("property"):
			var parts = line.split(" ")
			if parts.size() >= 3:
				properties.append(parts[2])

	print("PLYLoader: Loading %d gaussians..." % element_count)

	# Mapping properties to indices
	var prop_map: Dictionary = {}
	for i in range(properties.size()):
		prop_map[properties[i]] = i

	# Assume binary_little_endian for 3DGS results
	# Each property is a float32 (4 bytes)
	for i in range(element_count):
		var splat = GaussianSplat.new()

		# Read all properties for this vertex
		var data: Array[float] = []
		for p in range(properties.size()):
			data.append(file.get_float())

		# Map basic properties
		if prop_map.has("x"): splat.position.x = data[prop_map["x"]]
		if prop_map.has("y"): splat.position.y = data[prop_map["y"]]
		if prop_map.has("z"): splat.position.z = data[prop_map["z"]]

		# Opacity (logit -> sigmoid)
		if prop_map.has("opacity"):
			var logit = data[prop_map["opacity"]]
			splat.opacity = 1.0 / (1.0 + exp(-logit))

		# Scaling (log space -> exp)
		if prop_map.has("scale_0"): splat.scale.x = exp(data[prop_map["scale_0"]])
		if prop_map.has("scale_1"): splat.scale.y = exp(data[prop_map["scale_1"]])
		if prop_map.has("scale_2"): splat.scale.z = exp(data[prop_map["scale_2"]])

		# Rotation (quaternion from 4 components: rot_0, rot_1, rot_2, rot_3)
		if prop_map.has("rot_0") and prop_map.has("rot_1") and prop_map.has("rot_2") and prop_map.has("rot_3"):
			var q = Quaternion(
				data[prop_map["rot_0"]],
				data[prop_map["rot_1"]],
				data[prop_map["rot_2"]],
				data[prop_map["rot_3"]]
			)
			splat.rotation = q.normalized()

		# Color (f_dc SH degree-0)
		var r = 0.5
		var g = 0.5
		var b = 0.5
		if prop_map.has("f_dc_0"): r = 0.5 + 0.28209 * data[prop_map["f_dc_0"]]
		if prop_map.has("f_dc_1"): g = 0.5 + 0.28209 * data[prop_map["f_dc_1"]]
		if prop_map.has("f_dc_2"): b = 0.5 + 0.28209 * data[prop_map["f_dc_2"]]
		splat.color = Color(r, g, b, splat.opacity)

		# Compute derived render properties
		splat.compute_derived()

		splats.append(splat)

		# Progress reporting
		if i % 10000 == 0:
			print("PLYLoader: %d/%d loaded..." % [i, element_count])

	file.close()
	return splats
