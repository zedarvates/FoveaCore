extends RefCounted
class_name FoveaDependencyManager
## Single source of truth for the StudioTo3D external tools (Phase 1, F1).
##
## Wraps the legacy PATH-only probing of [StudioDependencyChecker] with a unified
## model: for each dependency it reports {found, version, resolved path, per-OS
## download URL}. Binaries installed by the integrated downloader (F2/F3) live
## under [code]user://fovea_tools/[/code] and are preferred over the system PATH,
## so the user never has to touch their PATH.
##
## F1 scope: status + resolution only. Downloading/installing is F2/F3.

## Local install root for tools fetched by the integrated installer.
const TOOLS_DIR := "user://fovea_tools"

## Tool registry: name → probe + per-OS download metadata.
## [code]bin[/code] is the executable basename expected under TOOLS_DIR/<name>/.
const TOOLS := {
	"ffmpeg": {
		"bin": "ffmpeg",
		"probe_args": ["-version"],
		"version_regex": "ffmpeg version ([^ ]+)",
		"urls": {
			"Windows": "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip",
			"Linux": "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz",
			"macOS": "https://evermeet.cx/ffmpeg/getrelease/zip",
		},
	},
	"colmap": {
		"bin": "colmap",
		"probe_args": ["--help"],
		"version_regex": "COLMAP ([0-9][^ \n]*)",
		"urls": {
			"Windows": "https://github.com/colmap/colmap/releases/latest",
			"Linux": "https://github.com/colmap/colmap/releases/latest",
			"macOS": "https://github.com/colmap/colmap/releases/latest",
		},
	},
	"python": {
		"bin": "python",
		"probe_args": ["--version"],
		"version_regex": "Python ([0-9][^ \n]*)",
		"urls": {
			# python-build-standalone (astral) — resolved precisely in F3.
			"Windows": "https://github.com/astral-sh/python-build-standalone/releases/latest",
			"Linux": "https://github.com/astral-sh/python-build-standalone/releases/latest",
			"macOS": "https://github.com/astral-sh/python-build-standalone/releases/latest",
		},
	},
}


## Returns the path to invoke [param name]: a local TOOLS_DIR binary if present,
## otherwise the bare command (resolved via the system PATH at run time).
static func resolve(name: String) -> String:
	if not TOOLS.has(name):
		return name
	var bin: String = TOOLS[name]["bin"]
	var local := _local_binary_path(name, bin)
	if local != "":
		return local
	return bin


## Probes a single tool. Returns {found: bool, version: String, path: String,
## source: "local"|"path"|"", download_url: String}.
static func probe(name: String) -> Dictionary:
	var result := {"found": false, "version": "", "path": "", "source": "", "download_url": download_url(name)}
	if not TOOLS.has(name):
		return result

	var info: Dictionary = TOOLS[name]
	var local := _local_binary_path(name, info["bin"])
	var exe := local if local != "" else String(info["bin"])

	var output: Array = []
	var code := OS.execute(exe, info["probe_args"], output, true, false)
	if code != 0:
		return result

	result["found"] = true
	result["path"] = exe
	result["source"] = "local" if local != "" else "path"
	result["version"] = _extract_version(output, info.get("version_regex", ""))
	return result


## Probes every registered tool. Returns {name: probe_dict}.
static func get_status() -> Dictionary:
	var status := {}
	for name in TOOLS:
		status[name] = probe(name)
	return status


## Per-OS download URL for [param name], or "" if unknown.
static func download_url(name: String) -> String:
	if not TOOLS.has(name):
		return ""
	return TOOLS[name]["urls"].get(OS.get_name(), "")


## True if every tool required for the minimal pipeline is available.
static func minimal_pipeline_ready() -> bool:
	var s := get_status()
	return s.get("ffmpeg", {}).get("found", false) and s.get("python", {}).get("found", false)


# ── internals ───────────────────────────────────────────────────────────────

static func _local_binary_path(name: String, bin: String) -> String:
	var ext := ".exe" if OS.get_name() == "Windows" else ""
	var candidate := "%s/%s/%s%s" % [TOOLS_DIR, name, bin, ext]
	if FileAccess.file_exists(candidate):
		return ProjectSettings.globalize_path(candidate)
	return ""

static func _extract_version(output: Array, pattern: String) -> String:
	if output.is_empty() or pattern == "":
		return ""
	var text := String(output[0])
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return ""
	var m := re.search(text)
	return m.get_string(1) if m else ""
