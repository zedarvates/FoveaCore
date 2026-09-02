extends SceneTree

const WriterScript := preload("res://addons/foveacore/scripts/fovea_4d_writer.gd")
const BASE_PATH: String = "res://test/fixtures/rust_v2_fixture.fovea"
const OUTPUT_PATH: String = "res://test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d"


func _init() -> void:
	var keyframes: Array[PackedVector3Array] = []
	for keyframe: int in range(2):
		var frame := PackedVector3Array()
		for z: int in range(2):
			for y: int in range(2):
				for x: int in range(2):
					frame.append(Vector3(x, y, z) * 0.01 + Vector3(0.02, 0.03, 0.04) * keyframe)
		keyframes.append(frame)
	var error: Error = WriterScript.write_sidecar(
		OUTPUT_PATH,
		BASE_PATH,
		Vector3i(2, 2, 2),
		keyframes,
		4.0,
		true,
		AABB(Vector3.ZERO, Vector3.ONE)
	)
	if error != OK:
		push_error("Fovea4D fixture generation failed: %s" % error_string(error))
		quit(1)
		return
	print("Generated deterministic GDScript FOVEA_4D fixture: %s" % OUTPUT_PATH)
	quit(0)
