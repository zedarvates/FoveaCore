extends SceneTree

const COMFYUI_SPLAT_BRIDGE := preload(
	"res://addons/foveacore/scripts/reconstruction/comfyui_splat_bridge.gd"
)

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_workflow_preparation()
	_test_artifact_discovery()
	_test_artifact_validation()
	_test_destination_validation()
	print("ComfyUI splat bridge: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_workflow_preparation() -> void:
	var bridge: Variant = COMFYUI_SPLAT_BRIDGE.new()
	var source_workflow: Dictionary = {
		"11": {
			"class_type": "LoadImage",
			"inputs": {"image": "old.png"},
		},
		"20": {
			"class_type": "SavePLY",
			"inputs": {"model": ["19", 0]},
		},
	}
	var prepared: Dictionary = bridge.prepare_workflow_with_uploaded_image(
		source_workflow,
		"11",
		"uploaded.png"
	)
	_expect("raw API graph is accepted", bool(prepared.get("ok", false)))
	var payload: Dictionary = prepared.get("workflow", {})
	var graph: Dictionary = payload.get("prompt", {})
	_expect("workflow is normalized into a prompt payload", graph.has("11"))
	_expect("uploaded image is injected", graph["11"]["inputs"]["image"] == "uploaded.png")
	_expect("upload source is explicit", graph["11"]["inputs"]["upload"] == "image")
	_expect("caller's workflow remains unchanged", source_workflow["11"]["inputs"]["image"] == "old.png")
	_expect(
		"unknown LoadImage node fails closed",
		not bool(bridge.prepare_workflow_with_uploaded_image(source_workflow, "99", "x.png").get("ok", true))
	)


func _test_artifact_discovery() -> void:
	var bridge: Variant = COMFYUI_SPLAT_BRIDGE.new()
	var history_entry: Dictionary = {
		"outputs": {
			"7": {"images": [{"filename": "preview.png", "type": "output"}]},
			"42": {
				"meshes": [{
					"filename": "garden.ply",
					"subfolder": "fovea/3dgs",
					"type": "output",
				}],
			},
		},
	}
	var artifact: Dictionary = bridge.find_first_splat_artifact(history_entry)
	_expect("3D artifact is found under an arbitrary output key", artifact.get("filename", "") == "garden.ply")
	_expect("artifact subfolder is preserved", artifact.get("subfolder", "") == "fovea/3dgs")
	_expect("artifact source node is reported", artifact.get("node_id", "") == "42")
	_expect(
		"image-only workflows fail closed",
		bridge.find_first_splat_artifact({"outputs": {"1": {"images": [{"filename": "only.png"}]}}}).is_empty()
	)


func _test_artifact_validation() -> void:
	var bridge: Variant = COMFYUI_SPLAT_BRIDGE.new()
	var fovea_bytes: PackedByteArray = "FOVEA_3Dpayload".to_ascii_buffer()
	_expect("native artifact magic is accepted", bridge.validate_artifact_bytes("asset.fovea", fovea_bytes).is_empty())
	_expect(
		"invalid native magic is rejected",
		not bridge.validate_artifact_bytes("asset.fovea", "NOT_FOVEA".to_ascii_buffer()).is_empty()
	)
	var splat_bytes := PackedByteArray()
	splat_bytes.resize(32)
	_expect("one-stride .splat artifact is accepted", bridge.validate_artifact_bytes("asset.splat", splat_bytes).is_empty())
	splat_bytes.resize(31)
	_expect("misaligned .splat artifact is rejected", not bridge.validate_artifact_bytes("asset.splat", splat_bytes).is_empty())
	var ply_bytes: PackedByteArray = "ply\nformat ascii 1.0\nelement vertex 0\nend_header\n".to_ascii_buffer()
	_expect("PLY header is accepted", bridge.validate_artifact_bytes("asset.ply", ply_bytes).is_empty())
	_expect("unsupported mesh artifact is rejected", not bridge.validate_artifact_bytes("asset.glb", ply_bytes).is_empty())


func _test_destination_validation() -> void:
	var bridge: Variant = COMFYUI_SPLAT_BRIDGE.new()
	_expect(
		"user data destination is accepted",
		bridge.validate_destination_path("user://fovea/comfyui/generated_test.ply").is_empty()
	)
	_expect(
		"machine-absolute destination is rejected",
		not bridge.validate_destination_path("C:/temp/generated.ply").is_empty()
	)
	_expect(
		"unsupported destination extension is rejected",
		not bridge.validate_destination_path("user://fovea/generated.glb").is_empty()
	)


func _expect(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		push_error("FAIL: " + label)
