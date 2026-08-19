extends SceneTree

## Non-GPU drift guard for the stable node, autoload facades, reconstruction API,
## and public specification evidence states. It checks active source signatures
## against the developer reference and keeps stale APIs/statuses from returning.

const DOC_PATH: String = "res://docs/developer_reference.md"
const SPEC_PATH: String = "res://docs/autowiki/spec.md"
const PROJECT_PATH: String = "res://project.godot"
const SPLAT_PATH: String = "res://addons/foveacore/scripts/fovea_splat_3d.gd"
const CORE_MANAGER_PATH: String = "res://addons/foveacore/scripts/foveacore_manager.gd"
const RECONSTRUCTION_MANAGER_PATH: String = "res://addons/foveacore/scripts/reconstruction/reconstruction_manager.gd"
const RECONSTRUCTION_BACKEND_PATH: String = "res://addons/foveacore/scripts/reconstruction/reconstruction_backend.gd"
const RECONSTRUCTION_SESSION_PATH: String = "res://addons/foveacore/scripts/reconstruction/reconstruction_session.gd"
const STUDIO_PROCESSOR_PATH: String = "res://addons/foveacore/scripts/reconstruction/studio_processor.gd"

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\nDeveloper Reference Contract Tests")
	var docs: String = _read_required("Developer reference", DOC_PATH)
	var spec: String = _read_required("Technical specification", SPEC_PATH)
	var project: String = _read_required("Project settings", PROJECT_PATH)
	var splat_source: String = _read_required("FoveaSplat3D source", SPLAT_PATH)
	var core_source: String = _read_required("FoveaCoreManager source", CORE_MANAGER_PATH)
	var manager_source: String = _read_required("Reconstruction manager source", RECONSTRUCTION_MANAGER_PATH)
	var backend_source: String = _read_required("Reconstruction backend source", RECONSTRUCTION_BACKEND_PATH)
	var session_source: String = _read_required("Reconstruction session source", RECONSTRUCTION_SESSION_PATH)
	var studio_source: String = _read_required("Studio processor source", STUDIO_PROCESSOR_PATH)

	_test_ownership(docs, project, splat_source, core_source, manager_source)
	_test_source_signatures(docs, "FoveaSplat3D", splat_source)
	_test_source_signatures(docs, "FoveaCoreManager", core_source)
	_test_source_signatures(docs, "ReconstructionManager", manager_source)
	_test_source_signatures(docs, "ReconstructionBackend", backend_source)
	_test_source_signatures(docs, "ReconstructionSession", session_source)
	_test_source_signatures(docs, "StudioProcessor", studio_source)
	_test_session_contract(docs, session_source, backend_source)
	_test_stale_api_rejection(docs)
	_test_spec_evidence_states(spec)

	print("Developer reference contract: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _read_required(label: String, path: String) -> String:
	var content: String = FileAccess.get_file_as_string(path)
	_assert("%s is readable" % label, not content.is_empty())
	return content

func _test_ownership(
	docs: String,
	project: String,
	splat_source: String,
	core_source: String,
	manager_source: String
) -> void:
	_assert("Reference carries the current validation date", docs.contains("updated 2026-08-15"))
	_assert("FoveaSplat3D class identity matches", splat_source.contains("class_name FoveaSplat3D") and docs.contains("Class `FoveaSplat3D`"))
	_assert("Core implementation class identity matches", core_source.contains("class_name FoveaCoreManagerScript") and docs.contains("class `FoveaCoreManagerScript`"))
	_assert("Reconstruction implementation class identity matches", manager_source.contains("class_name FoveaReconstructionManager") and docs.contains("class `FoveaReconstructionManager`"))
	_assert("Core autoload is registered and documented", project.contains("FoveaCoreManager=") and docs.contains("Autoload `FoveaCoreManager`"))
	_assert("Reconstruction autoload is registered and documented", project.contains("ReconstructionManager=") and docs.contains("Autoload `ReconstructionManager`"))

func _test_source_signatures(docs: String, label: String, source: String) -> void:
	var method_signatures: Array[String] = _extract_public_signatures(source, "func ")
	var signal_signatures: Array[String] = _extract_public_signatures(source, "signal ")
	var undocumented_methods: Array[String] = _find_undocumented(docs, method_signatures)
	var undocumented_signals: Array[String] = _find_undocumented(docs, signal_signatures)
	_assert(
		"%s public methods are documented%s" % [label, _missing_suffix(undocumented_methods)],
		undocumented_methods.is_empty()
	)
	_assert(
		"%s signals are documented%s" % [label, _missing_suffix(undocumented_signals)],
		undocumented_signals.is_empty()
	)

func _extract_public_signatures(source: String, prefix: String) -> Array[String]:
	var signatures: Array[String] = []
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with(prefix):
			continue
		var signature: String = line.trim_prefix(prefix).trim_suffix(":")
		if prefix == "func " and signature.begins_with("_"):
			continue
		signatures.append(signature)
	return signatures

func _find_undocumented(docs: String, signatures: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for signature: String in signatures:
		if not docs.contains("`%s`" % signature):
			missing.append(signature)
	return missing

func _missing_suffix(missing: Array[String]) -> String:
	if missing.is_empty():
		return ""
	return " (missing: %s)" % ", ".join(missing)

func _test_session_contract(docs: String, session_source: String, backend_source: String) -> void:
	_assert(
		"New sessions expose the 30,000-iteration default",
		session_source.contains("var training_iterations: int = 30000")
			and docs.contains("current new-session default is 30,000")
	)
	_assert(
		"Legacy iteration migration remains explicit",
		session_source.contains('dict.get("training_iterations", 7000)')
			and docs.contains("historical 7,000-iteration value")
	)
	_assert(
		"Training command consumes the session budget",
		backend_source.contains('str(session.training_iterations)')
			and docs.contains("`training_iterations`")
	)
	_assert(
		"Training point-cloud resolution is documented",
		session_source.contains("func get_training_point_cloud_path() -> String:")
			and docs.contains("`get_training_point_cloud_path() -> String`")
	)

func _test_stale_api_rejection(docs: String) -> void:
	_assert("Removed initialize facade stays absent", not docs.contains("- `initialize(config"))
	_assert("Removed phase_started signal stays absent", not docs.contains("phase_started("))
	_assert("Removed phase_progress signal stays absent", not docs.contains("phase_progress("))
	_assert("Removed cancel_reconstruction method stays absent", not docs.contains("cancel_reconstruction("))
	_assert("Reconstruction remains labeled experimental", docs.contains("Reconstruction is experimental"))

func _test_spec_evidence_states(spec: String) -> void:
	var public_node_section: String = _extract_section(spec, "### `FoveaSplat3D`")
	var manager_section: String = _extract_section(spec, "### `FoveaCoreManager`")
	var subsystem_section: String = _extract_section(spec, "### Subsystems")
	_assert(
		"FoveaSplat3D specification carries the validated headless boundary",
		public_node_section.contains("**State:** VALIDATED for headless lifecycle")
			and public_node_section.contains("representative rendering remains EXPERIMENTAL")
	)
	_assert(
		"FoveaCoreManager specification carries the validated facade boundary",
		manager_section.contains("**State:** VALIDATED for headless facade orchestration")
			and manager_section.contains("GPU and XR execution remain EXPERIMENTAL")
	)
	_assert(
		"Subsystem specification keeps hardware execution experimental",
		subsystem_section.contains("**State:** VALIDATED for headless ownership")
			and subsystem_section.contains("compute, XR, and performance remain EXPERIMENTAL")
	)
	_assert("No stale unvalidated state remains in the specification", not spec.contains("IMPLEMENTED_UNVALIDATED"))

func _extract_section(text: String, heading: String) -> String:
	var start: int = text.find(heading)
	if start < 0:
		return ""
	var next_heading: int = text.find("\n### ", start + heading.length())
	if next_heading < 0:
		return text.substr(start)
	return text.substr(start, next_heading - start)

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)
