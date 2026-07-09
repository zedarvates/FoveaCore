class_name FoveaFlipbookImporter
extends RefCounted
signal import_progress(frame: int, total: int)
signal import_complete(path: String, frame_count: int)
signal import_error(message: String)
@export var fps: float = 12.0
func import_sequence(folder_path: String, output_path: String) -> bool:
	var dir = DirAccess.open(folder_path)
	if not dir: push_error("Cannot open: " + folder_path); return false
	var files: Array[String] = []
	dir.list_dir_begin(); var f = dir.get_next()
	while f != "":
		if f.ends_with(".ply") or f.ends_with(".fovea"): files.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	if files.is_empty(): push_error("No .ply/.fovea files"); return false
	files.sort_custom(func(a, b): return _ns(a) < _ns(b))
	emit_signal("import_complete", output_path, files.size())
	return true
func _ns(name: String) -> String:
	var d = ""
	for c in name:
		if c.is_valid_int(): d += c
	return d.rpad(4, "0") if d else name
