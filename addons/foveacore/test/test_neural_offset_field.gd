extends SceneTree

const NeuralField = preload("res://addons/foveacore/scripts/advanced/fovea_neural_offset_field.gd")

func _init() -> void:

	var field: FoveaNeuralOffsetField = NeuralField.new()
	field.grid_dims = Vector3i(2, 2, 2)
	field.bounds_min = Vector3.ZERO
	field.bounds_max = Vector3.ONE
	field.offsets = PackedVector3Array()
	field.offsets.resize(8)
	for index: int in range(field.offsets.size()):
		field.offsets[index] = Vector3(0.5, 0.0, 0.0)
	assert(field.sample(Vector3(0.5, 0.5, 0.5), 0.0) == Vector3(0.5, 0.0, 0.0))
	print("PASS: neural field interpolates typed offsets")
	quit(0)
