extends Node
class_name ReconstructionExporter

signal export_started(format: String)
signal export_progress(current: int, total: int)
signal export_completed(output_path: String)
signal export_failed(reason: String)

enum ExportFormat { PLY, SPLAT, GLB, JSON_METADATA }

@export var export_quality: String = "high"

func export_session(session: ReconstructionSession, format: ExportFormat, output_path: String) -> bool:
	export_started.emit(ExportFormat.keys()[format])
	
	var input_path = ProjectSettings.globalize_path(session.output_directory)
	
	match format:
		ExportFormat.PLY:
			return _export_ply(input_path, output_path)
		ExportFormat.SPLAT:
			return _export_splat(input_path, output_path)
		ExportFormat.JSON_METADATA:
			return _export_metadata_json(session, output_path)
		_:
			export_failed.emit("Format non supporté: " + str(format))
			return false

func _export_ply(input_path: String, output_path: String) -> bool:
	var splat_file = input_path + "/point_cloud/points.ply"
	if not FileAccess.file_exists(splat_file):
		splat_file = input_path + "/splats.ply"
	
	if not FileAccess.file_exists(splat_file):
		export_failed.emit("Fichier splats source introuvable")
		return false
	
	var source = FileAccess.open(splat_file, FileAccess.READ)
	var dest = FileAccess.open(output_path, FileAccess.WRITE)
	
	if not source or not dest:
		export_failed.emit("Erreur d'ouverture des fichiers")
		return false
	
	var header_end = _find_header_end(source)
	source.seek(header_end)
	dest.store_string(_read_header(source))
	
	var line_count = 0
	while source.get_position() < source.get_length():
		var line = source.get_line()
		dest.store_line(line)
		line_count += 1
		if line_count % 1000 == 0:
			export_progress.emit(line_count, -1)
	
	source.close()
	dest.close()
	
	export_completed.emit(output_path)
	return true

func _find_header_end(file: FileAccess) -> int:
	file.seek(0)
	while file.get_position() < file.get_length():
		var line = file.get_line()
		if line.strip_edges().begins_with("end_header"):
			return file.get_position()
	return 0

func _read_header(file: FileAccess) -> String:
	file.seek(0)
	var header = ""
	while file.get_position() < file.get_length():
		var line = file.get_line()
		header += line + "\n"
		if line.strip_edges().begins_with("end_header"):
			break
	return header

func _export_splat(input_path: String, output_path: String) -> bool:
	var splat_file = input_path + "/point_cloud/points.ply"
	if not FileAccess.file_exists(splat_file):
		splat_file = input_path + "/splats.ply"
	
	if not FileAccess.file_exists(splat_file):
		export_failed.emit("Fichier splats source introuvable")
		return false
	
	var source = FileAccess.open(splat_file, FileAccess.READ)
	var dest = FileAccess.open(output_path, FileAccess.WRITE)
	
	if not source or not dest:
		export_failed.emit("Erreur d'ouverture des fichiers")
		return false
	
	var header_lines = []
	var vertex_count = 0
	
	while source.get_position() < source.get_length():
		var line = source.get_line()
		if line.begins_with("element vertex"):
			vertex_count = int(line.split(" ")[2])
		header_lines.append(line)
		if line.strip_edges().begins_with("end_header"):
			break
	
	for hl in header_lines:
		dest.store_line(hl)
	dest.store_line("end_header")
	
	var line_num = 0
	while source.get_position() < source.get_length():
		var line = source.get_line()
		dest.store_line(line)
		line_num += 1
		if line_num % 5000 == 0:
			export_progress.emit(line_num, vertex_count)
	
	source.close()
	dest.close()
	
	export_completed.emit(output_path)
	return true

func _export_metadata_json(session: ReconstructionSession, output_path: String) -> bool:
	var metadata = {
		"session_name": session.session_name,
		"created_at": Time.get_datetime_string_from_system(),
		"video_path": session.video_path,
		"frame_count": session.frame_count,
		"processing_settings": {
			"mask_mode": session.mask_mode,
			"background_threshold": session.background_threshold,
			"use_fast_sync": session.use_fast_sync
		},
		"output_directory": session.output_directory,
		"status": session.status,
		"quality_metrics": session.metrics.get_quality_report() if session.metrics else ""
	}
	
	var json = JSON.stringify(metadata, "\t")
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		export_failed.emit("Impossible de créer le fichier JSON")
		return false
	
	file.store_string(json)
	file.close()
	
	export_completed.emit(output_path)
	return true

func export_to_super_splat_format(session: ReconstructionSession, output_path: String) -> bool:
	return export_session(session, ExportFormat.SPLAT, output_path)

func export_quality_report_html(session: ReconstructionSession, output_path: String) -> bool:
	var html = """
<!DOCTYPE html>
<html>
<head>
	<meta charset="UTF-8">
	<title>Reconstruction Quality Report - %s</title>
	<style>
		body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
		       max-width: 900px; margin: 0 auto; padding: 20px; 
		       background: #1a1a2e; color: #eee; }
		h1 { color: #00d4ff; border-bottom: 2px solid #00d4ff; padding-bottom: 10px; }
		.metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }
		.metric { background: #16213e; padding: 20px; border-radius: 8px; 
		         border: 1px solid #0f3460; }
		.metric-label { font-size: 12px; color: #888; text-transform: uppercase; }
		.metric-value { font-size: 28px; color: #00d4ff; font-weight: bold; }
		.status { padding: 8px 16px; border-radius: 4px; display: inline-block; }
		.status-success { background: #00d4ff22; color: #00d4ff; }
		.status-error { background: #ff475722; color: #ff4757; }
		.preview { margin-top: 20px; border-radius: 8px; overflow: hidden; }
		.preview img { width: 100%%; height: auto; }
	</style>
</head>
<body>
	<h1>📊 Quality Report</h1>
	<p>Generated: %s</p>
	
	<div class="status %s">
		Status: %s
	</div>
	
	<div class="metrics">
		<div class="metric">
			<div class="metric-label">Frames</div>
			<div class="metric-value">%d</div>
		</div>
		<div class="metric">
			<div class="metric-label">Mask Coverage</div>
			<div class="metric-value">%.1f%%</div>
		</div>
		<div class="metric">
			<div class="metric-label">Processing Time</div>
			<div class="metric-value">%s</div>
		</div>
	</div>
	
	<h2>Details</h2>
	<table>
		<tr><td>Session:</td><td>%s</td></tr>
		<tr><td>Video:</td><td>%s</td></tr>
		<tr><td>Mask Mode:</td><td>%s</td></tr>
		<tr><td>Output:</td><td>%s</td></tr>
	</table>
	
	<h2>Quality Analysis</h2>
	<pre>%s</pre>
</body>
</html>
	""" % [
		session.session_name,
		Time.get_datetime_string_from_system(),
		"status-success" if session.status != "Erreur" else "status-error",
		session.status,
		session.frame_count,
		session.background_threshold * 100.0,
		"N/A",
		session.session_name,
		session.video_path.get_file(),
		session.mask_mode if session.mask_mode else "Smart Studio",
		session.output_directory,
		session.metrics.get_quality_report() if session.metrics else "No metrics available"
	]
	
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		export_failed.emit("Impossible de créer le rapport HTML")
		return false
	
	file.store_string(html)
	file.close()
	
	export_completed.emit(output_path)
	return true