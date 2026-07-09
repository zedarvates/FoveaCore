extends SceneTree
const NeuralField = preload("res://addons/foveacore/scripts/animation/fovea_neural_offset_field.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaNeuralOffsetField Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var n = NeuralField.new()
	assert(n.sample(Vector3.ZERO) == Vector3.ZERO, "Empty field returns zero")
	var data = PackedFloat32Array()
	data.resize(16*16*16*3)
	data[0] = 0.5; data[1] = 0.0; data[2] = 0.0
	n.bake_from_numpy(data, 16)
	var sampled = n.sample(Vector3.ZERO)
	assert(sampled != Vector3.ZERO, "Baked field samples")
	_passed += 2; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
