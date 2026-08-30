extends SceneTree

## Non-GPU guard for the canonical Rust and experimental C++ native artifacts.
## The C++ build must never overwrite the binary loaded by foveacore.gdextension.

const CANONICAL_DESCRIPTOR_PATH: String = "res://addons/foveacore/foveacore.gdextension"
const CI_DISABLED_DESCRIPTOR_PATH: String = "res://addons/foveacore/foveacore.gdextension.ci-disabled"
const CPP_DESCRIPTOR_TEMPLATE_PATH: String = "res://addons/foveacore/gdextension/foveacore_cpp.gdextension.example"
const CPP_SCONSTRUCT_PATH: String = "res://addons/foveacore/gdextension/SConstruct"
const CPP_REGISTRATION_PATH: String = "res://addons/foveacore/gdextension/src/register_types.cpp"
const CI_WORKFLOW_PATH: String = "res://.github/workflows/ci.yml"

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\nNative Extension Ownership Contract Tests")
	var canonical_descriptor: String = _read_canonical_descriptor()
	var cpp_descriptor: String = FileAccess.get_file_as_string(CPP_DESCRIPTOR_TEMPLATE_PATH)
	var sconstruct: String = FileAccess.get_file_as_string(CPP_SCONSTRUCT_PATH)
	var registration_source: String = FileAccess.get_file_as_string(CPP_REGISTRATION_PATH)
	var ci_workflow: String = FileAccess.get_file_as_string(CI_WORKFLOW_PATH)

	_assert("Canonical descriptor is readable", not canonical_descriptor.is_empty())
	_assert("C++ descriptor template is readable", not cpp_descriptor.is_empty())
	_assert("C++ SConstruct is readable", not sconstruct.is_empty())
	_assert("C++ registration source is readable", not registration_source.is_empty())
	_assert("CI workflow is readable", not ci_workflow.is_empty())

	_assert("Rust remains the canonical entry symbol", canonical_descriptor.contains('entry_symbol = "gdext_rust_init"'))
	_assert("Rust retains the canonical Windows artifact", canonical_descriptor.contains("bin/foveacore.dll"))
	_assert("C++ exports a distinct entry symbol", registration_source.contains("GDE_EXPORT foveacore_cpp_init("))
	_assert("C++ descriptor matches its entry symbol", cpp_descriptor.contains('entry_symbol = "foveacore_cpp_init"'))
	_assert("C++ descriptor uses a distinct artifact", cpp_descriptor.contains("bin/foveacore_cpp.dll"))
	_assert("C++ build uses a distinct artifact", sconstruct.contains('target="#bin/foveacore_cpp"'))
	_assert("C++ build cannot overwrite the canonical artifact", not sconstruct.contains('target="#bin/foveacore"'))
	_assert("C++ build fails closed outside its supported target", sconstruct.contains('platform != "windows"') and sconstruct.contains('target != "template_release"') and sconstruct.contains('arch != "x86_64"'))
	_assert("CI uploads the distinct C++ artifact", ci_workflow.contains("gdextension/bin/foveacore_cpp.dll"))

	print("Native extension ownership contract: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _read_canonical_descriptor() -> String:
	if FileAccess.file_exists(CANONICAL_DESCRIPTOR_PATH):
		return FileAccess.get_file_as_string(CANONICAL_DESCRIPTOR_PATH)
	if FileAccess.file_exists(CI_DISABLED_DESCRIPTOR_PATH):
		return FileAccess.get_file_as_string(CI_DISABLED_DESCRIPTOR_PATH)
	return ""

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)
