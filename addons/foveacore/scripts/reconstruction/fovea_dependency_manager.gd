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
const TOOLS_DIR: String = "user://fovea_tools"

## Tool registry: name → probe + per-OS download metadata.
## [code]bin[/code] is the executable basename expected under TOOLS_DIR/<name>/.
const TOOLS: Dictionary = {
	"ffmpeg": {
		"bin": "ffmpeg",
		"setting": "fovea/tools/ffmpeg_path",
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
		"setting": "fovea/tools/colmap_path",
		"probe_args": ["--help"],
		"version_regex": "COLMAP ([0-9][^ \n]*)",
		"urls": {
			"Windows": "https://github.com/colmap/colmap/releases/download/3.11.0/colmap-x64-windows-cuda.zip",
			"Linux": "https://github.com/colmap/colmap/releases/download/3.11.0/colmap-x86_64-linux.tar.gz",
			"macOS": "https://github.com/colmap/colmap/releases/download/3.11.0/colmap-x64-mac.zip",
		},
	},
	"python": {
		"bin": "python",
		"setting": "fovea/tools/python_path",
		"probe_args": ["--version"],
		"version_regex": "Python ([0-9][^ \n]*)",
		"urls": {
			"Windows": "https://github.com/indygreg/python-build-standalone/releases/download/20240107/cpython-3.10.13+20240107-x86_64-pc-windows-msvc-shared-install_only.tar.gz",
			"Linux": "https://github.com/indygreg/python-build-standalone/releases/download/20240107/cpython-3.10.13+20240107-x86_64-unknown-linux-gnu-install_only.tar.gz",
			"macOS": "https://github.com/indygreg/python-build-standalone/releases/download/20240107/cpython-3.10.13+20240107-x86_64-apple-darwin-install_only.tar.gz",
		},
	},
}


## Returns the command/path used to invoke [param name]. Resolution order:
## explicit project setting → local TOOLS_DIR binary → bare command (system PATH).
static func resolve(name: String) -> String:
	return _resolved(name)["path"] as String


## Probes a single tool. Returns {found: bool, version: String, path: String,
## source: "setting"|"local"|"path"|"", download_url: String}.
static func probe(name: String) -> Dictionary:
	var result: Dictionary = {"found": false, "version": "", "path": "", "source": "", "download_url": download_url(name)}
	if not TOOLS.has(name):
		return result

	var info: Dictionary = TOOLS[name]
	var res: Dictionary = _resolved(name)
	var exe: String = res["path"] as String

	var output: Array = []
	var code: int = OS.execute(exe, info["probe_args"] as Array[String], output, true, false)
	if code != 0:
		return result

	result["found"] = true
	result["path"] = exe
	result["source"] = res["source"]
	result["version"] = _extract_version(output, info.get("version_regex", "") as String)
	return result


## Probes every registered tool. Returns {name: probe_dict}.
static func get_status() -> Dictionary:
	var status: Dictionary = {}
	for name: String in TOOLS:
		status[name] = probe(name)
	return status


## Per-OS download URL for [param name], or "" if unknown.
static func download_url(name: String) -> String:
	if not TOOLS.has(name):
		return ""
	return TOOLS[name]["urls"].get(OS.get_name(), "") as String


## True if every tool required for the minimal pipeline is available.
static func minimal_pipeline_ready() -> bool:
	var s: Dictionary = get_status()
	return (s.get("ffmpeg", {}) as Dictionary).get("found", false) as bool and (s.get("python", {}) as Dictionary).get("found", false) as bool


# ── internals ───────────────────────────────────────────────────────────────

## Resolves a tool to {path, source}. Order: explicit project setting →
## local TOOLS_DIR install → bare command name (system PATH).
static func _resolved(name: String) -> Dictionary:
	if not TOOLS.has(name):
		return {"path": name, "source": "path"}
	var info: Dictionary = TOOLS[name]

	# 1. Explicit project setting (a deliberate user choice wins).
	var setting_key: String = info.get("setting", "") as String
	if setting_key != "" and ProjectSettings.has_setting(setting_key):
		var configured: String = String(ProjectSettings.get_setting(setting_key)).strip_edges()
		if configured != "":
			# An absolute/relative path must exist; a bare command is taken as-is.
			if ("/" in configured) or ("\\" in configured):
				if FileAccess.file_exists(configured):
					return {"path": configured, "source": "setting"}
			else:
				return {"path": configured, "source": "setting"}

	# 2. Binary installed by the integrated downloader under user://fovea_tools/.
	var local: String = _local_binary_path(name, info["bin"] as String)
	if local != "":
		return {"path": local, "source": "local"}

	# 3. Fall back to the bare command (resolved via PATH at run time).
	return {"path": String(info["bin"]), "source": "path"}

static func _local_binary_path(name: String, bin: String) -> String:
	var ext: String = ".exe" if OS.get_name() == "Windows" else ""
	var candidate: String = "%s/%s/%s%s" % [TOOLS_DIR, name, bin, ext]
	if name == "python" and OS.get_name() != "Windows":
		candidate = "%s/%s/bin/%s%s" % [TOOLS_DIR, name, bin, ext]
	if FileAccess.file_exists(candidate):
		return ProjectSettings.globalize_path(candidate)
	return ""

static func _extract_version(output: Array, pattern: String) -> String:
	if output.is_empty() or pattern == "":
		return ""
	var text: String = String(output[0])
	var re: RegEx = RegEx.new()
	if re.compile(pattern) != OK:
		return ""
	var m: RegExMatch = re.search(text)
	return m.get_string(1) if m else ""
