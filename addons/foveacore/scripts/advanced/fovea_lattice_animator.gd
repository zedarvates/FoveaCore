class_name FoveaLatticeAnimator
extends Node

## FoveaEngine — Lattice Cage Animator & Recorder
## Records, plays, and serializes lattice cage animation tracks to/from .fovea metadata.

@export var lattice_deformer: FoveaLatticeDeformer = null
@export var loop: bool = true
@export var playback_fps: float = 30.0

var is_playing: bool = false
var is_recording: bool = false

var _time: float = 0.0
var _recording_time: float = 0.0
var _keyframes: Array = [] # Array of dictionaries: {"time": float, "offsets": Array[Vector3]}
var _current_frame_idx: int = 0

func _ready() -> void:
	if lattice_deformer == null:
		var parent := get_parent()
		if parent is FoveaLatticeDeformer:
			lattice_deformer = parent

func _process(delta: float) -> void:
	if is_recording and lattice_deformer:
		_recording_time += delta
		var interval := 1.0 / playback_fps
		# Record a keyframe at fixed intervals
		if _keyframes.is_empty() or _recording_time - _keyframes[-1]["time"] >= interval:
			record_keyframe(_recording_time)
			
	elif is_playing and lattice_deformer and not _keyframes.is_empty():
		_time += delta
		var anim_length: float = _keyframes[-1]["time"]
		if _time > anim_length:
			if loop:
				_time = fmod(_time, anim_length)
			else:
				_time = anim_length
				is_playing = false
				
		_apply_playback_at_time(_time)

## Captures the current control offsets from the lattice deformer as a keyframe
func record_keyframe(time: float) -> void:
	if lattice_deformer == null:
		return
	var offsets: Array[Vector3] = []
	for v: Vector3 in lattice_deformer.control_offsets:
		offsets.append(v)
	_keyframes.append({
		"time": time,
		"offsets": offsets
	})
	print("FoveaLatticeAnimator: Recorded keyframe at %.2fs" % time)

## Starts playing the current keyframe animation
func play() -> void:
	if _keyframes.is_empty():
		push_warning("FoveaLatticeAnimator: No keyframes to play.")
		return
	is_playing = true
	is_recording = false
	_time = 0.0

## Starts recording keyframes
func start_recording() -> void:
	_keyframes.clear()
	_recording_time = 0.0
	is_recording = true
	is_playing = false
	print("FoveaLatticeAnimator: Started recording animation...")

## Stops recording keyframes
func stop_recording() -> void:
	is_recording = false
	print("FoveaLatticeAnimator: Stopped recording. Total keyframes: %d" % _keyframes.size())

func _apply_playback_at_time(t: float) -> void:
	if _keyframes.size() == 1:
		lattice_deformer.control_offsets = _keyframes[0]["offsets"]
		return
		
	# Find current and next keyframe
	var idx_curr := 0
	var idx_next := 1
	for i in range(_keyframes.size() - 1):
		if t >= _keyframes[i]["time"] and t <= _keyframes[i+1]["time"]:
			idx_curr = i
			idx_next = i + 1
			break
			
	var k_curr: Dictionary = _keyframes[idx_curr]
	var k_next: Dictionary = _keyframes[idx_next]
	
	var duration: float = k_next["time"] - k_curr["time"]
	var factor := 0.0
	if duration > 0.0001:
		factor = (t - k_curr["time"]) / duration
		
	var offsets_curr: Array = k_curr["offsets"]
	var offsets_next: Array = k_next["offsets"]
	
	var interp_offsets: Array[Vector3] = []
	for i in range(8):
		var v_curr: Vector3 = offsets_curr[i]
		var v_next: Vector3 = offsets_next[i]
		interp_offsets.append(v_curr.lerp(v_next, factor))
		
	lattice_deformer.control_offsets = interp_offsets

## Converts keyframes to a JSON-serializable dictionary
func get_animation_dictionary() -> Dictionary:
	var frames_data := []
	for k: Dictionary in _keyframes:
		var offsets_data := []
		for offset: Vector3 in k["offsets"]:
			offsets_data.append([offset.x, offset.y, offset.z])
		frames_data.append({
			"time": k["time"],
			"offsets": offsets_data
		})
	return {
		"fps": playback_fps,
		"keyframes": frames_data
	}

## Loads keyframes from a JSON dictionary
func load_animation_from_dictionary(dict: Dictionary) -> void:
	if not dict.has("keyframes"):
		return
	playback_fps = dict.get("fps", 30.0)
	_keyframes.clear()
	var frames_list: Array = dict["keyframes"]
	for f: Dictionary in frames_list:
		var t: float = f["time"]
		var raw_offsets: Array = f["offsets"]
		var offsets: Array[Vector3] = []
		for ro: Array in raw_offsets:
			offsets.append(Vector3(ro[0], ro[1], ro[2]))
		_keyframes.append({
			"time": t,
			"offsets": offsets
		})
	print("FoveaLatticeAnimator: Loaded animation with %d keyframes." % _keyframes.size())

## Writes the recorded animation directly into the .fovea asset file
func save_to_fovea_metadata(file_path: String) -> bool:
	if _keyframes.is_empty():
		push_error("FoveaLatticeAnimator: No keyframes to save.")
		return false
		
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("FoveaLatticeAnimator: Cannot open file for reading: " % file_path)
		return false
		
	# 1. Read header
	var magic := file.get_buffer(8)
	if magic.get_string_from_utf8() != "FOVEA_3D":
		push_error("FoveaLatticeAnimator: Invalid magic header in .fovea file.")
		return false
		
	var version := file.get_32()
	var splat_count := file.get_32()
	var color_codebook_size := file.get_32()
	var covar_codebook_size := file.get_32()
	var aabb_min := Vector3(file.get_float(), file.get_float(), file.get_float())
	var aabb_max := Vector3(file.get_float(), file.get_float(), file.get_float())
	var style_offset := file.get_32()
	var style_size := file.get_32()
	var mesh_offset := file.get_32()
	var mesh_size := file.get_32()
	var meta_offset := file.get_32()
	var meta_size := file.get_32()
	
	# Read entire file bytes to preserve existing sections
	file.seek(0)
	var file_bytes := file.get_buffer(file.get_length())
	file.close()
	
	# Extract core splat data bytes
	var splats_start := 72 + color_codebook_size * 12 + covar_codebook_size * 32
	var splats_end := splats_start + splat_count * 16
	var core_bytes := file_bytes.slice(0, splats_end)
	
	# Extract existing style and mesh data
	var style_bytes := PackedByteArray()
	if style_size > 0:
		style_bytes = file_bytes.slice(style_offset, style_offset + style_size)
	
	var mesh_bytes := PackedByteArray()
	if mesh_size > 0:
		mesh_bytes = file_bytes.slice(mesh_offset, mesh_offset + mesh_size)
		
	# Extract or initialize metadata dictionary
	var meta_dict := {}
	if meta_size > 0:
		var meta_bytes := file_bytes.slice(meta_offset, meta_offset + meta_size)
		var meta_str := meta_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(meta_str) == OK:
			meta_dict = json.data as Dictionary
			
	# Merge our lattice animation data into metadata
	meta_dict["lattice_animation"] = get_animation_dictionary()
	
	# Serialize updated metadata to JSON
	var new_meta_str := JSON.stringify(meta_dict)
	var new_meta_bytes := new_meta_str.to_utf8_buffer()
	
	# Reconstruct offsets and write new file
	var current_offset := splats_end
	
	var new_style_offset := 0
	if not style_bytes.is_empty():
		new_style_offset = current_offset
		current_offset += style_bytes.size()
		
	var new_mesh_offset := 0
	if not mesh_bytes.is_empty():
		new_mesh_offset = current_offset
		current_offset += mesh_bytes.size()
		
	var new_meta_offset := current_offset
	var new_meta_size := new_meta_bytes.size()
	
	# Overwrite/Create new .fovea file with updated header & appended sections
	var out_file := FileAccess.open(file_path, FileAccess.WRITE)
	if out_file == null:
		push_error("FoveaLatticeAnimator: Cannot open file for writing: " % file_path)
		return false
		
	# Write Header
	out_file.store_buffer(magic)
	out_file.store_32(version)
	out_file.store_32(splat_count)
	out_file.store_32(color_codebook_size)
	out_file.store_32(covar_codebook_size)
	out_file.store_float(aabb_min.x); out_file.store_float(aabb_min.y); out_file.store_float(aabb_min.z)
	out_file.store_float(aabb_max.x); out_file.store_float(aabb_max.y); out_file.store_float(aabb_max.z)
	out_file.store_32(new_style_offset)
	out_file.store_32(style_size)
	out_file.store_32(new_mesh_offset)
	out_file.store_32(mesh_size)
	out_file.store_32(new_meta_offset)
	out_file.store_32(new_meta_size)
	
	# Write color codebook, covar codebook, and splats (already in core_bytes after header)
	out_file.store_buffer(core_bytes.slice(72))
	
	# Append sections
	if not style_bytes.is_empty():
		out_file.store_buffer(style_bytes)
	if not mesh_bytes.is_empty():
		out_file.store_buffer(mesh_bytes)
		
	out_file.store_buffer(new_meta_bytes)
	out_file.close()
	
	print("FoveaLatticeAnimator: Successfully saved lattice animation to .fovea metadata!")
	return true

## Loads the lattice animation from the metadata of a .fovea asset file
func load_from_fovea_metadata(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false
		
	# Skip to meta_offset in header (at offset 64)
	file.seek(64)
	var meta_offset := file.get_32()
	var meta_size := file.get_32()
	
	if meta_size == 0 or meta_offset == 0:
		file.close()
		return false
		
	file.seek(meta_offset)
	var meta_bytes := file.get_buffer(meta_size)
	file.close()
	
	var meta_str := meta_bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(meta_str) != OK:
		return false
		
	var meta_dict: Dictionary = json.data
	if meta_dict.has("lattice_animation"):
		load_animation_from_dictionary(meta_dict["lattice_animation"])
		return true
		
	return false
