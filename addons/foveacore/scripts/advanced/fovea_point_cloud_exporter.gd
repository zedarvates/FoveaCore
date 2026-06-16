class_name FoveaPointCloudExporter
extends RefCounted

## FoveaPointCloudExporter — Exports Gaussian Splats to Standard Point Clouds
## Clean splats based on opacity/scale and format them as PLY or XYZ for ML processing (MeshFlow).

## Export configuration parameters
class ExportConfig:
	var min_opacity: float = 0.15
	var max_scale: float = 0.05
	var target_points_count: int = 32768
	var use_binary: bool = true
	var filter_isolated_floaters: bool = true
	var floater_radius: float = 0.2
	var floater_min_neighbors: int = 3

## Exports the splats from a FoveaSplattable to a PLY file.
static func export_splattable_to_ply(splattable: FoveaSplattable, dest_path: String, config: ExportConfig = null) -> bool:
	if splattable == null:
		push_error("FoveaPointCloudExporter: Splattable is null.")
		return false
		
	if splattable.loaded_splats.is_empty():
		push_error("FoveaPointCloudExporter: No loaded splats in Splattable: " + splattable.name)
		return false
		
	if config == null:
		config = ExportConfig.new()
		
	return export_splats_to_ply(splattable.loaded_splats, dest_path, config)

## Exports an array of GaussianSplats to a PLY point cloud file.
static func export_splats_to_ply(splats: Array[GaussianSplat], dest_path: String, config: ExportConfig) -> bool:
	print("FoveaPointCloudExporter: Starting point cloud export to ", dest_path)
	
	# 1. Filter splats based on opacity and scale threshold
	var filtered_splats: Array[GaussianSplat] = []
	for splat in splats:
		if splat.opacity >= config.min_opacity and splat.scale.length() <= config.max_scale:
			filtered_splats.append(splat)
			
	print("FoveaPointCloudExporter: Opacity/Scale filtering: %d -> %d splats." % [splats.size(), filtered_splats.size()])
	
	if filtered_splats.is_empty():
		push_error("FoveaPointCloudExporter: No splats left after filtering.")
		return false

	# 2. Filter floaters (isolated points) if requested
	if config.filter_isolated_floaters:
		filtered_splats = _remove_isolated_floaters(filtered_splats, config.floater_radius, config.floater_min_neighbors)
		print("FoveaPointCloudExporter: Floater filtering: %d splats remaining." % filtered_splats.size())
		
	# 3. Downsample or upsample to match target_points_count for MeshFlow (ideal: fixed 16384 or 32768 points)
	var final_splats: Array[GaussianSplat] = []
	if filtered_splats.size() > config.target_points_count:
		# Downsample: Uniform random sampling or grid sampling
		# Here we do a deterministic shuffle-based downsampling to preserve uniform spatial coverage
		var step = float(filtered_splats.size()) / config.target_points_count
		for i in range(config.target_points_count):
			var idx = int(floor(i * step))
			if idx < filtered_splats.size():
				final_splats.append(filtered_splats[idx])
	else:
		# Not enough points, keep all filtered points (MeshFlow encoders can pad remaining points)
		final_splats = filtered_splats
		
	print("FoveaPointCloudExporter: Final point count for export: %d." % final_splats.size())
	
	# 4. Write to PLY file
	var file = FileAccess.open(dest_path, FileAccess.WRITE)
	if not file:
		push_error("FoveaPointCloudExporter: Cannot open destination path for writing: " + dest_path)
		return false
		
	# Write PLY Header
	file.store_line("ply")
	if config.use_binary:
		file.store_line("format binary_little_endian 1.0")
	else:
		file.store_line("format ascii 1.0")
		
	file.store_line("element vertex %d" % final_splats.size())
	file.store_line("property float x")
	file.store_line("property float y")
	file.store_line("property float z")
	file.store_line("property float opacity")
	file.store_line("property uchar red")
	file.store_line("property uchar green")
	file.store_line("property uchar blue")
	file.store_line("end_header")
	
	if config.use_binary:
		# Write Binary Little Endian
		for splat in final_splats:
			file.store_float(splat.position.x)
			file.store_float(splat.position.y)
			file.store_float(splat.position.z)
			file.store_float(splat.opacity)
			
			var r = int(clamp(splat.color.r * 255.0, 0.0, 255.0))
			var g = int(clamp(splat.color.g * 255.0, 0.0, 255.0))
			var b = int(clamp(splat.color.b * 255.0, 0.0, 255.0))
			file.store_8(r)
			file.store_8(g)
			file.store_8(b)
	else:
		# Write ASCII
		for splat in final_splats:
			var r = int(clamp(splat.color.r * 255.0, 0.0, 255.0))
			var g = int(clamp(splat.color.g * 255.0, 0.0, 255.0))
			var b = int(clamp(splat.color.b * 255.0, 0.0, 255.0))
			var line = "%f %f %f %f %d %d %d" % [
				splat.position.x,
				splat.position.y,
				splat.position.z,
				splat.opacity,
				r, g, b
			]
			file.store_line(line)
			
	file.close()
	print("FoveaPointCloudExporter: Successfully wrote point cloud PLY to ", dest_path)
	return true

## Simplified floater removal using spatial hash grid
static func _remove_isolated_floaters(splats: Array[GaussianSplat], radius: float, min_neighbors: int) -> Array[GaussianSplat]:
	var survivors: Array[GaussianSplat] = []
	var grid: Dictionary = {}
	
	# Voxel grid cell size matches floater radius
	var cell_size = radius
	
	# Pass 1: Bucket splats into spatial hash
	for i in range(splats.size()):
		var pos = splats[i].position
		var cell = Vector3i(
			int(floor(pos.x / cell_size)),
			int(floor(pos.y / cell_size)),
			int(floor(pos.z / cell_size))
		)
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(i)
		
	# Pass 2: Filter splats based on neighbor density in adjacent voxels
	for i in range(splats.size()):
		var pos = splats[i].position
		var cell = Vector3i(
			int(floor(pos.x / cell_size)),
			int(floor(pos.y / cell_size)),
			int(floor(pos.z / cell_size))
		)
		
		var neighbors_count = 0
		# Search 3x3x3 neighborhood
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var neighbor_cell = cell + Vector3i(dx, dy, dz)
					if grid.has(neighbor_cell):
						for other_idx in grid[neighbor_cell]:
							if other_idx != i:
								var other_pos = splats[other_idx].position
								if pos.distance_squared_to(other_pos) <= radius * radius:
									neighbors_count += 1
									
		if neighbors_count >= min_neighbors:
			survivors.append(splats[i])
			
	return survivors
