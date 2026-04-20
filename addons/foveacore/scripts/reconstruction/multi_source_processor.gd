extends Node
class_name MultiSourceProcessor

signal source_added(index: int, path: String)
signal sources_merged(output_path: String)
signal merge_failed(reason: String)

var video_sources: Array[String] = []
var _processor: StudioProcessor = null

func _ready() -> void:
	_processor = StudioProcessor.new()
	add_child(_processor)

func add_video_source(path: String) -> int:
	if not FileAccess.file_exists(path):
		push_error("MultiSourceProcessor: File not found: " + path)
		return -1
	
	video_sources.append(path)
	var idx = video_sources.size() - 1
	source_added.emit(idx, path)
	print("MultiSourceProcessor: Added source #%d: %s" % [idx, path.get_file()])
	return idx

func add_video_sources(paths: PackedStringArray) -> int:
	var added = 0
	for path in paths:
		if add_video_source(path) >= 0:
			added += 1
	return added

func get_source_count() -> int:
	return video_sources.size()

func get_source_info(index: int) -> Dictionary:
	if index < 0 or index >= video_sources.size():
		return {}
	
	var path = video_sources[index]
	var info = {
		"index": index,
		"path": path,
		"filename": path.get_file(),
		"basename": path.get_file().get_basename(),
		"extension": path.get_extension()
	}
	return info

func merge_all_sources(session: ReconstructionSession) -> bool:
	if video_sources.size() < 2:
		push_warning("MultiSourceProcessor: Need at least 2 sources to merge")
		return false
	
	var output_dir = ProjectSettings.globalize_path(session.output_directory + "/merged_input")
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	
	var frame_offset = 0
	var total_frames = 0
	
	for src_idx in range(video_sources.size()):
		var source_path = video_sources[src_idx]
		var temp_dir = OS.get_user_data_dir() + "/fovea_temp_merge_%d" % src_idx
		
		if DirAccess.dir_exists_absolute(temp_dir):
			DirAccess.remove_recursive(temp_dir)
		DirAccess.make_dir_recursive_absolute(temp_dir)
		
		var args = [
			"-i", ProjectSettings.globalize_path(source_path),
			"-vf", "fps=2",
			"-q:v", "2",
			temp_dir + "/frame_%04d.jpg"
		]
		
		var cmd = _processor.ffmpeg_path if not _processor.ffmpeg_path.is_empty() else "ffmpeg"
		var pid = OS.create_process(cmd, args)
		
		while OS.is_process_running(pid):
			await get_tree().create_timer(0.5).timeout
		
		var source_frames = _count_frames_in_dir(temp_dir)
		
		var dest_offset = output_dir + "/%s_" % [get_source_info(src_idx)["filename"]]
		for i in range(source_frames):
			var src_frame = temp_dir + "/frame_%04d.jpg" % (i + 1)
			var dest_frame = dest_offset + "frame_%04d.jpg" % (i + 1 + frame_offset)
			if FileAccess.file_exists(src_frame):
				var img = Image.load_from_file(src_frame)
				if img:
					img.save_jpg(dest_frame)
		
		frame_offset += source_frames
		total_frames += source_frames
		
		if DirAccess.dir_exists_absolute(temp_dir):
			DirAccess.remove_recursive(temp_dir)
	
	session.frame_count = total_frames
	session.output_directory = session.output_directory.replace("/input", "/merged_input")
	
	sources_merged.emit(output_dir)
	print("MultiSourceProcessor: Merged %d sources into %d frames" % [video_sources.size(), total_frames])
	return true

func _count_frames_in_dir(dir_path: String) -> int:
	var count = 0
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if file.ends_with(".jpg"):
				count += 1
			file = dir.get_next()
	return count

func estimate_combined_duration() -> float:
	var total = 0.0
	for path in video_sources:
		var args = [
			"-i", ProjectSettings.globalize_path(path),
			"-f", "null",
			"-"
		]
		var cmd = _processor.ffmpeg_path if not _processor.ffmpeg_path.is_empty() else "ffmpeg"
		var out = []
		OS.execute(cmd, args, out)
		
		for line in out:
			if "Duration:" in line:
				var duration_str = line.split("Duration:")[1].split(",")[0].strip_edges()
				var parts = duration_str.split(":")
				if parts.size() == 3:
					var hours = float(parts[0])
					var mins = float(parts[1])
					var secs = float(parts[2])
					total += hours * 3600 + mins * 60 + secs
				break
	return total

func get_combined_info() -> Dictionary:
	return {
		"source_count": video_sources.size(),
		"sources": video_sources.map(func(p): return p.get_file()),
		"estimated_duration": estimate_combined_duration()
	}