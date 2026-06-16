extends SceneTree

## Unit tests for FoveaSurfaceDeformer
## Validates wave height deformation and local wave slope rotation alignment.

const FoveaSurfaceDeformer = preload("res://addons/foveacore/scripts/advanced/fovea_surface_deformer.gd")

var _passed := 0
var _failed := 0

signal test_passed(test_name: String, details: String)
signal test_failed(test_name: String, error: String)
signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaSurfaceDeformer Unit Tests")
	print("=".repeat(70))
	
	await create_timer(0.3).timeout
	_run_all()

func _run_all() -> void:
	# 1. Create a mock MultiMesh
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 3
	
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf := PackedFloat32Array()
	buf.resize(3 * stride)
	
	# Initial positions for 3 splats
	var positions := [
		Vector3(-0.5, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0)
	]
	for i in range(3):
		FoveaMultiMeshBulk.write_transform(buf, i * stride, Transform3D(Basis(), positions[i]))
	mm.buffer = buf
	
	# 2. Create FoveaCoreSplatRenderer and attach MultiMesh
	var renderer := FoveaCoreSplatRenderer.new()
	root.add_child(renderer)
	renderer.multimesh = mm
	
	# 3. Instantiate FoveaSurfaceDeformer
	var deformer := FoveaSurfaceDeformer.new()
	deformer.wave_speed = 1.0
	deformer.wave_amplitude = 0.5
	deformer.wave_frequency = 1.0
	deformer.wave_tiling_size = 10.0
	deformer.type = FoveaSurfaceDeformer.DeformationType.GERSTNER_WAVES
	renderer.add_child(deformer)
	
	# Run one process frame to initialize cache and apply deformation
	deformer._process(0.016)
	
	# Retrieve updated MultiMesh transforms from buffer
	var updated_buf: PackedFloat32Array = mm.buffer
	
	# Splat 1 index 0
	var s1_pos := Vector3(updated_buf[3], updated_buf[7], updated_buf[11])
	var s1_basis_x := Vector3(updated_buf[0], updated_buf[4], updated_buf[8])
	var s1_basis_y := Vector3(updated_buf[1], updated_buf[5], updated_buf[9])
	var s1_basis_z := Vector3(updated_buf[2], updated_buf[6], updated_buf[10])
	
	# Assertions
	_assert("Splat 1 translated vertically by wave", s1_pos.y != 0.0, "La hauteur du splat doit être modifiée")
	
	# Verifier la rotation : le basis Z ne doit plus être aligné avec Vector3.FORWARD ou Vector3.BACK pur
	_assert("Splat 1 rotated to follow wave slope (Z-axis tilted)", abs(s1_basis_z.x) > 0.01 or abs(s1_basis_z.z) < 0.99, "L'axe normal du splat doit s'incliner")
	
	# Verifier la preservation de l'echelle : le repère de rotation doit rester orthogonal et de longueur 1.0
	_assert_approx("Splat basis X length preserved (1.0)", s1_basis_x.length(), 1.0, 0.01)
	_assert_approx("Splat basis Y length preserved (1.0)", s1_basis_y.length(), 1.0, 0.01)
	_assert_approx("Splat basis Z length preserved (1.0)", s1_basis_z.length(), 1.0, 0.01)
	
	# 4. Test RIPPLES deformation
	deformer.type = FoveaSurfaceDeformer.DeformationType.RIPPLES
	deformer.trigger_ripple(Vector3(0.0, 0.0, 0.0), 1.0, 2.0, 5.0, 0.5, 1.0)
	
	# Process 0.2 seconds to propagate wave
	deformer._process(0.2)
	
	var rip_buf: PackedFloat32Array = mm.buffer
	var s3_offset := 2 * stride
	var s3_rip_pos := Vector3(rip_buf[s3_offset + 3], rip_buf[s3_offset + 7], rip_buf[s3_offset + 11])
	var s3_rip_basis_z := Vector3(rip_buf[s3_offset + 2], rip_buf[s3_offset + 6], rip_buf[s3_offset + 10])
	
	_assert("Splat 3 translated vertically by ripple", s3_rip_pos.y != 0.0, "La hauteur du splat 3 doit être modifiée par la ride")
	_assert("Splat 3 rotated to follow ripple slope (Z-axis tilted)", abs(s3_rip_basis_z.x) > 0.01 or abs(s3_rip_basis_z.z) < 0.99, "L'axe normal du splat 3 doit s'incliner sous l'effet de la ride")
	
	# Process 11.0 more seconds to let the ripple decay completely
	deformer._process(11.0)
	
	var decay_buf: PackedFloat32Array = mm.buffer
	var s3_decay_pos := Vector3(decay_buf[s3_offset + 3], decay_buf[s3_offset + 7], decay_buf[s3_offset + 11])
	
	_assert_approx("Splat 3 returned to baseline height after decay", s3_decay_pos.y, 0.0, 0.001)
	_assert("Ripples list is empty after decay", deformer._ripples.is_empty(), "Toutes les rides doivent être nettoyées après leur max_age")
	
	# Cleanup
	renderer.queue_free()
	
	# Report
	print("\n" + "=".repeat(70))
	print("FoveaSurfaceDeformer Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	all_complete.emit(_passed, _failed)
	quit()

func _assert(test_name: String, condition: bool, err_msg: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % test_name)
		test_passed.emit(test_name, "")
	else:
		_failed += 1
		print("  ✗ %s — %s" % [test_name, err_msg])
		test_failed.emit(test_name, err_msg)

func _assert_approx(test_name: String, value: float, expected: float, epsilon: float, err_msg: String = "") -> void:
	var diff := abs(value - expected)
	if diff <= epsilon:
		_passed += 1
		print("  ✓ %s (%.4f ≈ %.4f)" % [test_name, value, expected])
		test_passed.emit(test_name, "")
	else:
		_failed += 1
		print("  ✗ %s — %s (%.4f != %.4f, diff=%.4f)" % [test_name, err_msg, value, expected, diff])
		test_failed.emit(test_name, err_msg)
