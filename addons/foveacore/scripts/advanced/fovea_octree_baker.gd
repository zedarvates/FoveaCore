extends RefCounted
class_name FoveaOctreeBaker

## FoveaOctreeBaker
## Génère un octree spatial CPU et le sérialise dans un buffer Vulkan
## pour accélérer le culling GPU-driven sur les décors statiques.

class OctreeNode:
	var aabb: AABB
	var is_leaf: bool = true
	var child_start: int = -1 # Index du premier enfant dans le tableau global
	var splat_start: int = -1 # Offset du premier splat dans le buffer de splats triés
	var splat_count: int = 0
	var children: Array = [] # Array[OctreeNode]

# Bâtit l'octree et réorganise les splats
static func bake_octree(splats: Array, max_leaf_size: int = 4096, max_depth: int = 6) -> Dictionary:
	if splats.is_empty():
		return { "nodes_bytes": PackedByteArray(), "sorted_splats": [] }

	# 1. Calculer l'AABB globale
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	for s in splats:
		var pos: Vector3 = s.position
		aabb_min.x = minf(aabb_min.x, pos.x)
		aabb_min.y = minf(aabb_min.y, pos.y)
		aabb_min.z = minf(aabb_min.z, pos.z)
		aabb_max.x = maxf(aabb_max.x, pos.x)
		aabb_max.y = maxf(aabb_max.y, pos.y)
		aabb_max.z = maxf(aabb_max.z, pos.z)
		
	var root_aabb := AABB(aabb_min, aabb_max - aabb_min)
	var sorted_splats: Array = []
	
	# 2. Construction récursive de l'arbre
	var root := _build_node(splats, root_aabb, 0, max_leaf_size, max_depth, sorted_splats)
	
	# 3. Sérialisation plate des nœuds
	var nodes_bytes := serialize_octree(root)
	
	print("FoveaOctreeBaker: Octree baked. Total splats: %d, nodes serialized: %d bytes." % [
		splats.size(), nodes_bytes.size()
	])
	
	return {
		"nodes_bytes": nodes_bytes,
		"sorted_splats": sorted_splats,
		"root": root
	}

# Construit l'octree directement depuis un PackedByteArray
static func bake_octree_from_bytes(bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3, loader: RefCounted, max_leaf_size: int = 4096, max_depth: int = 6) -> Dictionary:
	if bytes.is_empty():
		return { "nodes_bytes": PackedByteArray(), "sorted_bytes": PackedByteArray(), "root": null }
		
	var total_splats := bytes.size() / 16
	var splats := []
	splats.resize(total_splats)
	
	var aabb_size = aabb_max - aabb_min
	for i in range(total_splats):
		var offset = i * 16
		var qx = bytes.decode_u16(offset)
		var qy = bytes.decode_u16(offset + 2)
		var qz = bytes.decode_u16(offset + 4)
		
		var px = aabb_min.x + (float(qx) / 65535.0) * aabb_size.x
		var py = aabb_min.y + (float(qy) / 65535.0) * aabb_size.y
		var pz = aabb_min.z + (float(qz) / 65535.0) * aabb_size.z
		
		splats[i] = {
			"position": Vector3(px, py, pz),
			"index": i
		}
		
	var root_aabb := AABB(aabb_min, aabb_size)
	var sorted_positions: Array = []
	
	var root := _build_node_temp(splats, root_aabb, 0, max_leaf_size, max_depth, sorted_positions)
	var nodes_bytes := serialize_octree(root)
	
	# Réordonner les octets via Rust (DirectStorage / fast reordering)
	var sorted_indices := PackedInt32Array()
	sorted_indices.resize(total_splats)
	for i in range(total_splats):
		sorted_indices[i] = sorted_positions[i].index
		
	var sorted_bytes: PackedByteArray = loader.reorder_splats(bytes, sorted_indices)
	
	return {
		"nodes_bytes": nodes_bytes,
		"sorted_bytes": sorted_bytes,
		"root": root
	}

static func _build_node_temp(node_splats: Array, aabb: AABB, depth: int, max_leaf_size: int, max_depth: int, splats_out: Array) -> OctreeNode:
	var node := OctreeNode.new()
	node.aabb = aabb
	
	if node_splats.size() <= max_leaf_size or depth >= max_depth:
		node.is_leaf = true
		node.splat_start = splats_out.size()
		node.splat_count = node_splats.size()
		splats_out.append_array(node_splats)
		return node
		
	node.is_leaf = false
	var half_size := aabb.size * 0.5
	var center := aabb.position + half_size
	
	var child_buckets := []
	child_buckets.resize(8)
	for i in range(8):
		child_buckets[i] = []
		
	for s in node_splats:
		var pos: Vector3 = s.position
		var x_idx := 0 if pos.x < center.x else 1
		var y_idx := 0 if pos.y < center.y else 1
		var z_idx := 0 if pos.z < center.z else 1
		var octant := x_idx + (y_idx << 1) + (z_idx << 2)
		child_buckets[octant].append(s)
		
	for i in range(8):
		var cx := i & 1
		var cy := (i >> 1) & 1
		var cz := (i >> 2) & 1
		var child_pos := aabb.position + Vector3(cx * half_size.x, cy * half_size.y, cz * half_size.z)
		var child_aabb := AABB(child_pos, half_size)
		
		if not child_buckets[i].is_empty():
			var child_node = _build_node_temp(child_buckets[i], child_aabb, depth + 1, max_leaf_size, max_depth, splats_out)
			node.children.append(child_node)
		else:
			var empty_node = OctreeNode.new()
			empty_node.aabb = child_aabb
			empty_node.is_leaf = true
			empty_node.splat_count = 0
			node.children.append(empty_node)
			
	return node

static func _build_node(node_splats: Array, aabb: AABB, depth: int, max_leaf_size: int, max_depth: int, splats_out: Array) -> OctreeNode:
	var node := OctreeNode.new()
	node.aabb = aabb
	
	# Condition d'arrêt : feuille atteinte
	if node_splats.size() <= max_leaf_size or depth >= max_depth:
		node.is_leaf = true
		node.splat_start = splats_out.size()
		node.splat_count = node_splats.size()
		splats_out.append_array(node_splats)
		return node
		
	node.is_leaf = false
	var half_size := aabb.size * 0.5
	var center := aabb.position + half_size
	
	# Initialiser les 8 octants
	var child_buckets := []
	child_buckets.resize(8)
	for i in range(8):
		child_buckets[i] = []
		
	# Distribuer les splats dans les octants
	for s in node_splats:
		var pos: Vector3 = s.position
		var x_idx := 0 if pos.x < center.x else 1
		var y_idx := 0 if pos.y < center.y else 1
		var z_idx := 0 if pos.z < center.z else 1
		var octant := x_idx + (y_idx << 1) + (z_idx << 2)
		child_buckets[octant].append(s)
		
	# Construire les sous-nœuds
	for i in range(8):
		var cx := i & 1
		var cy := (i >> 1) & 1
		var cz := (i >> 2) & 1
		var child_pos := aabb.position + Vector3(cx * half_size.x, cy * half_size.y, cz * half_size.z)
		var child_aabb := AABB(child_pos, half_size)
		
		if not child_buckets[i].is_empty():
			var child_node = _build_node(child_buckets[i], child_aabb, depth + 1, max_leaf_size, max_depth, splats_out)
			node.children.append(child_node)
		else:
			# Nœud vide pour maintenir la structure régulière à 8 enfants
			var empty_node = OctreeNode.new()
			empty_node.aabb = child_aabb
			empty_node.is_leaf = true
			empty_node.splat_count = 0
			node.children.append(empty_node)
			
	return node

static func serialize_octree(root: OctreeNode) -> PackedByteArray:
	var nodes_list: Array[OctreeNode] = []
	_flatten_tree(root, nodes_list)
	
	var bytes := PackedByteArray()
	bytes.resize(nodes_list.size() * 48)
	
	for i in range(nodes_list.size()):
		var n = nodes_list[i]
		var offset = i * 48
		
		# aabb_min (x, y, z, is_leaf)
		bytes.encode_float(offset, n.aabb.position.x)
		bytes.encode_float(offset + 4, n.aabb.position.y)
		bytes.encode_float(offset + 8, n.aabb.position.z)
		bytes.encode_float(offset + 12, 1.0 if n.is_leaf else 0.0)
		
		# aabb_max (x, y, z, start_index)
		bytes.encode_float(offset + 16, n.aabb.end.x)
		bytes.encode_float(offset + 20, n.aabb.end.y)
		bytes.encode_float(offset + 24, n.aabb.end.z)
		
		var start_index = n.splat_start if n.is_leaf else n.child_start
		bytes.encode_float(offset + 28, float(start_index))
		
		# count + padding
		var count = n.splat_count if n.is_leaf else n.children.size()
		bytes.encode_u32(offset + 32, count)
		bytes.encode_u32(offset + 36, 0)
		bytes.encode_u32(offset + 40, 0)
		bytes.encode_u32(offset + 44, 0)
		
	return bytes

static func _flatten_tree(node: OctreeNode, list: Array[OctreeNode]) -> int:
	var idx = list.size()
	list.append(node)
	
	if not node.is_leaf:
		node.child_start = list.size()
		# Ajouter tous les enfants consécutivement pour un accès GPU direct
		for child in node.children:
			list.append(child)
			
		# Aplatir récursivement les sous-arbres des enfants
		for child in node.children:
			if not child.is_leaf:
				_flatten_descendants(child, list)
				
	return idx

static func _flatten_descendants(node: OctreeNode, list: Array[OctreeNode]) -> void:
	node.child_start = list.size()
	for child in node.children:
		list.append(child)
	for child in node.children:
		if not child.is_leaf:
			_flatten_descendants(child, list)
