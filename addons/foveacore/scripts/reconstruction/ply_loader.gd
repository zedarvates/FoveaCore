extends RefCounted
class_name PLYLoader

## PLYLoader — Specializes in loading Gaussian Splatting .ply files
## Parses binary and ASCII formats containing positions, opacities, scales, and rotations.

const GaussianSplat = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

static func load_gaussians_from_ply(path: String) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []

	if not FileAccess.file_exists(path):
		push_error("PLYLoader: File not found: " + path)
		return splats

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("PLYLoader: Cannot open file: " + path)
		return splats

	# Parse Header
	var line = file.get_line().strip_edges()
	if line != "ply":
		push_error("PLYLoader: Not a valid PLY file.")
		file.close()
		return splats

	var element_count = 0
	var properties: Array[Dictionary] = [] # Array of {name: String, type: String}
	var is_binary := false

	while line != "end_header":
		# Guard against a truncated header (missing end_header): without this,
		# get_line() returns "" forever at EOF and the loop spins indefinitely.
		if file.eof_reached():
			push_error("PLYLoader: Truncated PLY header (no end_header): " + path)
			file.close()
			return splats
		line = file.get_line().strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("format"):
			if line.contains("binary"):
				is_binary = true
		elif line.begins_with("element vertex"):
			element_count = line.split(" ")[2].to_int()
		elif line.begins_with("property"):
			var parts = line.split(" ")
			if parts.size() >= 3:
				properties.append({
					"type": parts[1],
					"name": parts[2]
				})

	print("PLYLoader: Loading %d gaussians (%s format)..." % [element_count, "binary" if is_binary else "ascii"])

	# Mapping properties to indices
	var prop_map: Dictionary = {}
	for i in range(properties.size()):
		prop_map[properties[i]["name"]] = i

	if is_binary:
		for i in range(element_count):
			if file.eof_reached():
				break
				
			var splat = GaussianSplat.new()

			# Read all properties for this vertex based on their declared type
			var data: Array[float] = []
			data.resize(properties.size())
			for p in range(properties.size()):
				data[p] = _read_property(file, properties[p]["type"])

			_map_properties_to_splat(splat, data, prop_map, properties)
			splats.append(splat)

			if i > 0 and i % 25000 == 0:
				print("PLYLoader: %d/%d loaded..." % [i, element_count])
	else:
		# ASCII format parsing
		for i in range(element_count):
			var vertex_line = file.get_line().strip_edges()
			if vertex_line.is_empty():
				if file.eof_reached():
					break
				continue
				
			var parts = vertex_line.split(" ", false)
			if parts.size() < properties.size():
				continue

			var splat = GaussianSplat.new()
			var data: Array[float] = []
			data.resize(properties.size())
			for p in range(properties.size()):
				data[p] = parts[p].to_float()

			_map_properties_to_splat(splat, data, prop_map, properties)
			splats.append(splat)

			if i > 0 and i % 25000 == 0:
				print("PLYLoader: %d/%d loaded..." % [i, element_count])

	file.close()
	print("PLYLoader: Successfully loaded %d splats." % splats.size())
	return splats

static func _read_property(file: FileAccess, type: String) -> float:
	match type:
		"float":
			return file.get_float()
		"double":
			return file.get_double()
		"uchar", "char", "uint8", "int8":
			return float(file.get_8())
		"ushort", "short", "uint16", "int16":
			return float(file.get_16())
		"uint", "int", "uint32", "int32":
			return float(file.get_32())
		_:
			return file.get_float()

static func _map_properties_to_splat(splat: GaussianSplat, data: Array, prop_map: Dictionary, properties: Array[Dictionary]) -> void:
	if prop_map.has("x"): splat.position.x = data[prop_map["x"]]
	if prop_map.has("y"): splat.position.y = data[prop_map["y"]]
	if prop_map.has("z"): splat.position.z = data[prop_map["z"]]

	# Opacity (logit -> sigmoid)
	if prop_map.has("opacity"):
		var logit = data[prop_map["opacity"]]
		splat.opacity = 1.0 / (1.0 + exp(-logit))
	else:
		splat.opacity = 0.8 # default

	# Scaling (log space -> exp)
	if prop_map.has("scale_0"): splat.scale.x = exp(data[prop_map["scale_0"]])
	if prop_map.has("scale_1"): splat.scale.y = exp(data[prop_map["scale_1"]])
	if prop_map.has("scale_2"): splat.scale.z = exp(data[prop_map["scale_2"]])

	# Rotation (quaternion rot_0, rot_1, rot_2, rot_3 in standard 3DGS order: w, x, y, z)
	if prop_map.has("rot_0") and prop_map.has("rot_1") and prop_map.has("rot_2") and prop_map.has("rot_3"):
		var q = Quaternion(
			data[prop_map["rot_1"]], # x
			data[prop_map["rot_2"]], # y
			data[prop_map["rot_3"]], # z
			data[prop_map["rot_0"]]  # w
		)
		splat.rotation = q.normalized()

	# Color (f_dc SH degree-0 or raw RGB)
	var r = 0.5
	var g = 0.5
	var b = 0.5
	if prop_map.has("f_dc_0") and prop_map.has("f_dc_1") and prop_map.has("f_dc_2"):
		r = 0.5 + 0.28209 * data[prop_map["f_dc_0"]]
		g = 0.5 + 0.28209 * data[prop_map["f_dc_1"]]
		b = 0.5 + 0.28209 * data[prop_map["f_dc_2"]]
	elif prop_map.has("red") and prop_map.has("green") and prop_map.has("blue"):
		var red_val = data[prop_map["red"]]
		var green_val = data[prop_map["green"]]
		var blue_val = data[prop_map["blue"]]
		
		# If uchar, normalize [0, 255] to [0, 1]
		var red_type = properties[prop_map["red"]]["type"]
		if red_type.contains("char") or red_type.contains("8"):
			r = red_val / 255.0
			g = green_val / 255.0
			b = blue_val / 255.0
		else:
			r = red_val
			g = green_val
			b = blue_val
			
	splat.color = Color(r, g, b, splat.opacity)
	splat.compute_derived()
