extends SceneTree

# Unit test for GPU Skinning Compute Shader (Task 265)

const DispatcherClass := preload("res://addons/foveacore/scripts/advanced/fovea_splat_dispatcher.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("FoveaEngine - GPU Skinning Compute Shader Unit Tests")
	print("======================================================================")
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	_test_lbs_skinning()
	_test_dqs_skinning()
	_finish()

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)

func _test_lbs_skinning() -> void:
	print("\n--- Test 1: Linear Blend Skinning (LBS) ---")
	
	var dispatcher := DispatcherClass.new()
	if not dispatcher.rd:
		_assert("RenderingDevice active", false)
		return
	
	# 1. Préparer 1 splat au centre de l'AABB (local coords 0.5, 0.5, 0.5)
	# local_pos = aabb_min + vec3(qx, qy, qz) / 65535 * size
	var splats_bytes := PackedByteArray()
	splats_bytes.resize(16)
	splats_bytes.encode_u16(0, 32768) # qx = 32768 (~0.5)
	splats_bytes.encode_u16(2, 32768) # qy = 32768 (~0.5)
	splats_bytes.encode_u16(4, 32768) # qz = 32768 (~0.5)
	# Les autres bytes sont 0 (normals, color, opacity, etc.)
	
	# 2. Influence: Bone 0 (weight 50%) et Bone 1 (weight 50%)
	# struct BoneInfluence { uint bone_indices; uint bone_weights; }
	var influences_bytes := PackedByteArray()
	influences_bytes.resize(8)
	# indices: bone 0 (index 0) et bone 1 (index 1)
	influences_bytes.encode_u32(0, 0x00000100) # bone 0 at byte 0, bone 1 at byte 1
	# weights: 128 (~0.5) and 127 (~0.5)
	influences_bytes.encode_u32(4, 0x00007F80) # weight 128 (0x80) at byte 0, weight 127 (0x7F) at byte 1
	
	# 3. Matrices d'os:
	# Matrix 0: translation de (2.0, 0.0, 0.0)
	# Matrix 1: translation de (0.0, 4.0, 0.0)
	var bone_transforms := PackedFloat32Array([
		# Matrix 0
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		2.0, 0.0, 0.0, 1.0,
		# Matrix 1
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		0.0, 4.0, 0.0, 1.0
	])
	
	var aabb_min := Vector3(-10.0, -10.0, -10.0)
	var aabb_max := Vector3(10.0, 10.0, 10.0)
	# aabb_size = (20, 20, 20)
	# local_pos = (-10, -10, -10) + (0.5, 0.5, 0.5) * 20 = (0, 0, 0)
	
	var deformed_bytes := dispatcher.dispatch_skinning(
		splats_bytes,
		influences_bytes,
		bone_transforms,
		false, # LBS
		aabb_min,
		aabb_max
	)
	
	_assert("LBS returned deformed bytes", deformed_bytes.size() == 16)
	if deformed_bytes.size() == 16:
		var nqx := deformed_bytes.decode_u16(0)
		var nqy := deformed_bytes.decode_u16(2)
		var nqz := deformed_bytes.decode_u16(4)
		
		# Calcul attendu:
		# Pos_neutre = (0, 0, 0)
		# Pos_deformed = 0.5 * (Pos_neutre + (2, 0, 0)) + 0.5 * (Pos_neutre + (0, 4, 0)) = (1.0, 2.0, 0.0)
		# Quantized: nq = (final_pos - aabb_min) / aabb_size * 65535
		# nqx = (1.0 - (-10.0)) / 20.0 * 65535 = 11.0 / 20.0 * 65535 = 36044
		# nqy = (2.0 - (-10.0)) / 20.0 * 65535 = 12.0 / 20.0 * 65535 = 39321
		# nqz = (0.0 - (-10.0)) / 20.0 * 65535 = 10.0 / 20.0 * 65535 = 32768
		
		print("    Expected final pos quantized: x~36044, y~39321, z~32768")
		print("    Actual final pos quantized:   x=%d, y=%d, z=%d" % [nqx, nqy, nqz])
		
		_assert("LBS position X close to expected", abs(int(nqx) - 36044) < 10)
		_assert("LBS position Y close to expected", abs(int(nqy) - 39321) < 10)
		_assert("LBS position Z close to expected", abs(int(nqz) - 32768) < 10)
		
	dispatcher.cleanup()

func _test_dqs_skinning() -> void:
	print("\n--- Test 2: Dual Quaternion Skinning (DQS) ---")
	
	var dispatcher := DispatcherClass.new()
	if not dispatcher.rd:
		_assert("RenderingDevice active", false)
		return
		
	var splats_bytes := PackedByteArray()
	splats_bytes.resize(16)
	splats_bytes.encode_u16(0, 32768) # center
	splats_bytes.encode_u16(2, 32768)
	splats_bytes.encode_u16(4, 32768)
	
	var influences_bytes := PackedByteArray()
	influences_bytes.resize(8)
	influences_bytes.encode_u32(0, 0x00000100) # bones 0 & 1
	influences_bytes.encode_u32(4, 0x00007F80) # 50% / 50%
	
	var bone_transforms := PackedFloat32Array([
		# Matrix 0
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		2.0, 0.0, 0.0, 1.0,
		# Matrix 1
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		0.0, 4.0, 0.0, 1.0
	])
	
	var aabb_min := Vector3(-10.0, -10.0, -10.0)
	var aabb_max := Vector3(10.0, 10.0, 10.0)
	
	var deformed_bytes := dispatcher.dispatch_skinning(
		splats_bytes,
		influences_bytes,
		bone_transforms,
		true, # DQS enabled
		aabb_min,
		aabb_max
	)
	
	_assert("DQS returned deformed bytes", deformed_bytes.size() == 16)
	if deformed_bytes.size() == 16:
		var nqx := deformed_bytes.decode_u16(0)
		var nqy := deformed_bytes.decode_u16(2)
		var nqz := deformed_bytes.decode_u16(4)
		
		# DQS on pure translations should produce the same linear translation: (1.0, 2.0, 0.0)
		print("    Expected final pos quantized: x~36044, y~39321, z~32768")
		print("    Actual final pos quantized:   x=%d, y=%d, z=%d" % [nqx, nqy, nqz])
		
		_assert("DQS position X close to expected", abs(int(nqx) - 36044) < 10)
		_assert("DQS position Y close to expected", abs(int(nqy) - 39321) < 10)
		_assert("DQS position Z close to expected", abs(int(nqz) - 32768) < 10)
		
	dispatcher.cleanup()

func _finish() -> void:
	print("\n======================================================================")
	print("GPU Skinning Unit Tests Summary:")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("======================================================================")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
