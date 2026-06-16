extends SceneTree
## Tests for FoveaDependencyManager (Phase 1, F1).
## Structural only — asserts the status model, not which tools happen to be
## installed (so it is portable across dev machines and CI). Non-GPU group.

const DepMgr := preload("res://addons/foveacore/scripts/reconstruction/fovea_dependency_manager.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaDependencyManager Tests (F1)")
	print("=".repeat(70))

	var status: Dictionary = DepMgr.get_status()
	_assert("status has ffmpeg/colmap/python",
		status.has("ffmpeg") and status.has("colmap") and status.has("python"),
		str(status.keys()))

	for name in ["ffmpeg", "colmap", "python"]:
		var p: Dictionary = status[name]
		_assert("%s probe has required keys" % name,
			p.has("found") and p.has("version") and p.has("path") and p.has("download_url"),
			str(p.keys()))
		_assert("%s found is bool" % name, p["found"] is bool, str(p["found"]))
		# A per-OS download URL must exist for every tool.
		_assert("%s has a download URL" % name, String(p["download_url"]) != "", str(p["download_url"]))
		# Consistency: if found, a path and source must be set.
		if p["found"]:
			_assert("%s found ⇒ path set" % name, String(p["path"]) != "", str(p["path"]))
			_assert("%s found ⇒ source in {local,path}" % name,
				p["source"] in ["local", "path"], str(p["source"]))

	# resolve() returns the bare command when nothing is installed locally.
	_assert("resolve(ffmpeg) non-empty", DepMgr.resolve("ffmpeg") != "", DepMgr.resolve("ffmpeg"))
	_assert("resolve(unknown) echoes name", DepMgr.resolve("nope") == "nope", "")

	# download_url respects the current OS.
	_assert("download_url(ffmpeg) non-empty for this OS",
		DepMgr.download_url("ffmpeg") != "", OS.get_name())

	# minimal_pipeline_ready returns a bool without crashing.
	_assert("minimal_pipeline_ready is bool",
		DepMgr.minimal_pipeline_ready() is bool, str(DepMgr.minimal_pipeline_ready()))

	print("\n" + "=".repeat(70))
	print("DependencyManager Tests: %d passed, %d failed" % [_passed, _failed])
	print("=".repeat(70))
	quit(1 if _failed > 0 else 0)

func _assert(name: String, cond: bool, detail: String) -> void:
	if cond:
		_passed += 1
		print("  ✓ %s — %s" % [name, detail])
	else:
		_failed += 1
		print("  ✗ %s — %s" % [name, detail])
