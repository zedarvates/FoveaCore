extends RefCounted
class_name FoveaSpatialChunk

var index: int
var aabb: AABB
var raw_bytes: PackedByteArray = PackedByteArray() # LOD 0 (100% density)
var raw_bytes_lod1: PackedByteArray = PackedByteArray() # LOD 1 (~50% density)
var raw_bytes_lod2: PackedByteArray = PackedByteArray() # LOD 2 (~20% density)
var raw_bytes_lod3: PackedByteArray = PackedByteArray() # LOD 3 (~5% density)
var is_loaded: bool = false
