extends SceneTree

# Unit test for FoveaStreamingManager (Out-of-Core SSD->VRAM chunk streaming)

const StreamingManagerClass := preload("res://addons/foveacore/scripts/advanced/fovea_streaming_manager.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("FoveaEngine - Streaming Manager Unit Tests")
	print("======================================================================")
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	_test_morton_encoding()
	_test_lru_eviction()
	_finish()

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)

func _test_morton_encoding() -> void:
	print("\n--- Test 1: Morton 3D encoding/decoding ---")
	
	# Test roundtrip Morton encoding for a cell index
	var x := 5
	var y := 10
	var z := 3
	
	var code := StreamingManagerClass.morton_encode_3d(x, y, z)
	var decoded := StreamingManagerClass.morton_decode_3d(code)
	
	_assert("Morton X matches after roundtrip", decoded.x == x)
	_assert("Morton Y matches after roundtrip", decoded.y == y)
	_assert("Morton Z matches after roundtrip", decoded.z == z)

func _test_lru_eviction() -> void:
	print("\n--- Test 2: LRU cache budget eviction ---")
	
	var manager := StreamingManagerClass.new()
	# Forcer un budget très bas (poids max en splats = 20)
	manager.max_ram_splats = 20
	_assert("RAM budget initialized correctly", manager.max_ram_splats == 20)
	
	var asset_path := "user://test_stream.fovea"
	# Créer un faux asset dans le manager
	var asset := StreamingManagerClass.StreamingAsset.new()
	asset.path = asset_path
	asset.chunks.resize(5)
	
	for i in range(5):
		var chunk := FoveaSpatialChunk.new()
		chunk.index = i
		chunk.is_loaded = false
		chunk.raw_bytes = PackedByteArray()
		# slices fictifs pour passer la garde get_meta
		chunk.set_meta("file_slices", [{ "offset": 0, "size": 160 }])
		asset.chunks[i] = chunk
		
	# Enregistrer l'asset
	manager._assets[asset_path] = asset
	
	# Simuler le chargement manuel de chunks
	# Chunk 0 : charge 10 splats (160 octets)
	var c0: FoveaSpatialChunk = asset.chunks[0]
	c0.raw_bytes.resize(160)
	c0.is_loaded = true
	manager._current_ram_splats += 10
	manager._touch_lru(asset_path + "_0")
	
	# Chunk 1 : charge 8 splats (128 octets)
	var c1: FoveaSpatialChunk = asset.chunks[1]
	c1.raw_bytes.resize(128)
	c1.is_loaded = true
	manager._current_ram_splats += 8
	manager._touch_lru(asset_path + "_1")
	
	_assert("RAM splat count is 18 (below budget)", manager._current_ram_splats == 18)
	
	# Chunk 2 : charge 5 splats (80 octets), ce qui dépasse le budget (total=23 > 20)
	# Devrait évincer le plus ancien chargé (Chunk 0)
	var c2: FoveaSpatialChunk = asset.chunks[2]
	c2.raw_bytes.resize(80)
	c2.is_loaded = true
	manager._current_ram_splats += 5
	manager._touch_lru(asset_path + "_2")
	
	# Appliquer le budget
	manager._enforce_ram_budget()
	
	_assert("Eviction occurred", manager._current_ram_splats <= 20)
	_assert("Chunk 0 was evicted (oldest)", not c0.is_loaded)
	_assert("Chunk 0 bytes cleared", c0.raw_bytes.is_empty())
	_assert("Chunk 1 is still loaded", c1.is_loaded)
	_assert("Chunk 2 is still loaded", c2.is_loaded)

func _finish() -> void:
	print("\n======================================================================")
	print("Streaming Manager Unit Tests Summary:")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("======================================================================")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
