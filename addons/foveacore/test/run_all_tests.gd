extends SceneTree

## run_all_tests.gd — Master test runner for FoveaCore.
## Scans test scripts and executes them directly or via test_node_runner.gd depending on their base class.

var _passed_scripts := 0
var _failed_scripts := 0
var _skipped_scripts := 0
var _failed_files := []

## Test group filter. Override with --group=nogpu | gpu | all (default: all).
## - "nogpu": skip suites marked `const REQUIRES_GPU := true` (CI hard-fail job).
## - "gpu":   run ONLY GPU suites (self-hosted / local job with a real GPU).
## - "all":   run everything (default; local dev).
var _group := "all"

func _init() -> void:
	if _has_cli_flag("--self-test-semantic-failure"):
		_run_semantic_classifier_self_test()
		return

	_group = _parse_group()

	print("\n" + "======================================================================")
	print("🚀 RUNNING FOVEACORE TESTS SEQUENTIALLY  (group=%s)" % _group)
	print("======================================================================")

	await create_timer(0.1).timeout

	var godot_bin = OS.get_executable_path()
	var test_dir = "res://addons/foveacore/test"
	var tests := []

	var dir = DirAccess.open(test_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".gd"):
				if (file_name.begins_with("test_") or file_name.ends_with("_test.gd")) \
					and file_name != "test_compile_all_scripts.gd" \
					and file_name != "run_all_tests.gd" \
					and file_name != "test_node_runner.gd":
					tests.append(test_dir.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()

	tests.sort()

	print("Found %d test scripts to evaluate." % tests.size())

	for test_path in tests:
		var script = load(test_path)
		if not script:
			print("  ✗ ERROR: Failed to load script: %s" % test_path)
			_failed_scripts += 1
			_failed_files.append(test_path)
			continue

		# Route by GPU requirement vs the selected group.
		var requires_gpu: bool = bool(script.get_script_constant_map().get("REQUIRES_GPU", false))
		var requires_integration: bool = bool(script.get_script_constant_map().get("REQUIRES_INTEGRATION", false))
		if _group == "nogpu" and requires_integration:
			_skipped_scripts += 1
			print("\n  ⏭  SKIP (nogpu): %s [integration]" % test_path.get_file())
			continue
		if not _should_run(requires_gpu):
			_skipped_scripts += 1
			print("\n  ⏭  SKIP (%s): %s [%s]" % [
				_group, test_path.get_file(), "GPU" if requires_gpu else "non-GPU"])
			continue

		print("\n" + "----------------------------------------------------------------------")
		print("Checking & Running: %s%s" % [
			test_path.get_file(), "  [GPU]" if requires_gpu else ""])
		print("----------------------------------------------------------------------")

		var base_type = script.get_instance_base_type()
		print("  Base type: %s" % base_type)
		
		var output = []
		var args := []
		
		# Chemin projet explicite : robuste quel que soit le cwd (CI, éditeur, terminal)
		var project_path: String = ProjectSettings.globalize_path("res://")

		if base_type == "SceneTree" or base_type == "MainLoop":
			args = ["--path", project_path, "-s", test_path, "--headless"]
		else:
			# Use node runner for Node, RefCounted, etc.
			args = ["--path", project_path, "-s", "res://addons/foveacore/test/test_node_runner.gd", test_path, "--headless"]

		# Propagate command line arguments if any (but not our own --group selector)
		for arg in OS.get_cmdline_args():
			if arg.begins_with("--") and arg != "--headless" \
				and not arg.begins_with("--path") and not arg.begins_with("--group"):
				args.append(arg)
				
		var exit_code = OS.execute(godot_bin, args, output, true)
		
		# Print output and reject semantic failure markers even when a generic
		# Node wrapper returns exit code 0.
		var output_text := ""
		if not output.is_empty():
			output_text = str(output[0])
			print(output_text)
		var semantic_failure: bool = _has_semantic_failure(output_text)
			
		if exit_code == 0 and not semantic_failure:
			_passed_scripts += 1
			print("  ✓ SUCCESS: %s" % test_path.get_file())
		else:
			_failed_scripts += 1
			_failed_files.append(test_path)
			print("  ✗ FAILED: %s (Exit code: %d, semantic marker: %s)" % [
				test_path.get_file(), exit_code, str(semantic_failure)])
			
	print("\n" + "======================================================================")
	print("FOVEACORE TEST RUNNER SUMMARY  (group=%s):" % _group)
	print("  Total Scripts Executed: %d" % (_passed_scripts + _failed_scripts))
	print("  Passed: %d" % _passed_scripts)
	print("  Failed: %d" % _failed_scripts)
	print("  Skipped (out of group): %d" % _skipped_scripts)
	if _failed_scripts > 0:
		print("  Failed Scripts:")
		for f in _failed_files:
			print("    - %s" % f.get_file())
	print("======================================================================")

	quit(1 if _failed_scripts > 0 else 0)


func _run_semantic_classifier_self_test() -> void:
	var cases: Array[Dictionary] = [
		{"name": "bracketed failure", "output": "[FAIL] assertion", "expected": true},
		{"name": "indented failure", "output": "\n  FAIL: assertion", "expected": true},
		{"name": "script error", "output": "SCRIPT ERROR: invalid call", "expected": true},
		{"name": "parse error", "output": "Parse Error: unexpected token", "expected": true},
		{"name": "clean output", "output": "42 passed, 0 failed", "expected": false},
	]
	var failed: int = 0
	for case: Dictionary in cases:
		var detected: bool = _has_semantic_failure(str(case["output"]))
		var expected: bool = bool(case["expected"])
		if detected == expected:
			print("RUNNER_CLASSIFIER: PASS — %s" % str(case["name"]))
		else:
			failed += 1
			print("RUNNER_CLASSIFIER: FAIL — %s" % str(case["name"]))
	print("Runner semantic classifier: %d passed, %d failed" % [cases.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _has_semantic_failure(output_text: String) -> bool:
	return output_text.contains("[FAIL]") \
		or output_text.contains("\n  FAIL:") \
		or output_text.contains("SCRIPT ERROR:") \
		or output_text.contains("Parse Error:")


func _has_cli_flag(flag: String) -> bool:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	arguments.append_array(OS.get_cmdline_args())
	return flag in arguments


## Reads the --group=<value> command-line argument. Defaults to "all".
func _parse_group() -> String:
	# Accept both the canonical user-argument form (`-- --group=nogpu`) and the
	# legacy direct form so older local scripts cannot silently run every suite.
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	arguments.append_array(OS.get_cmdline_args())
	for arg: String in arguments:
		if arg.begins_with("--group="):
			var val := arg.substr("--group=".length()).strip_edges().to_lower()
			if val in ["all", "nogpu", "gpu"]:
				return val
			push_warning("run_all_tests: unknown --group value '%s', falling back to 'all'." % val)
	return "all"


## Decides whether a suite runs given its GPU requirement and the active group.
func _should_run(requires_gpu: bool) -> bool:
	match _group:
		"nogpu":
			return not requires_gpu
		"gpu":
			return requires_gpu
		_:
			return true
