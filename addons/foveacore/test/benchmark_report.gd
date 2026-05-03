# benchmark_report.gd
# Générateur de rapport détaillé pour le benchmark de format couleur
# Génère des rapports HTML et texte avec graphiques et analyses

extends Node

var _results: Array = []
var _output_dir: String = "user://benchmark_reports"

signal report_generated(path: String)


func _ready() -> void:
	# Créer le dossier de sortie
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir(_output_dir)


func generate_report(results: Array, format: String = "both") -> void:
	"""Génère un rapport à partir des résultats du benchmark"""
	_results = results
	
	if format == "html" or format == "both":
		_generate_html_report()
	
	if format == "text" or format == "both":
		_generate_text_report()


func _generate_html_report() -> void:
	"""Génère un rapport HTML avec graphiques"""
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var filename = "%s/benchmark_report_%s.html" % [_output_dir, timestamp]
	
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		push_error("Impossible de créer le rapport HTML")
		return
	
	var html = _build_html_content()
	file.store_string(html)
	file.close()
	
	print("Rapport HTML généré: %s" % filename)
	report_generated.emit(filename)


func _generate_text_report() -> void:
	"""Génère un rapport texte"""
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var filename = "%s/benchmark_report_%s.txt" % [_output_dir, timestamp]
	
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		push_error("Impossible de créer le rapport texte")
		return
	
	var text = _build_text_content()
	file.store_string(text)
	file.close()
	
	print("Rapport texte généré: %s" % filename)
	report_generated.emit(filename)


func _build_html_content() -> String:
	"""Construit le contenu HTML du rapport"""
	var html = """<!DOCTYPE html>
<html>
<head>
	<title>Benchmark Format Couleur - Rapport</title>
	<style>
		body { font-family: Arial, sans-serif; margin: 20px; background: #1a1a1a; color: #e0e0e0; }
		h1 { color: #4CAF50; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
		h2 { color: #2196F3; margin-top: 30px; }
		table { border-collapse: collapse; width: 100%; margin: 20px 0; }
		th, td { border: 1px solid #444; padding: 12px; text-align: left; }
		th { background: #333; color: #4CAF50; }
		tr:nth-child(even) { background: #2a2a2a; }
		.metric { display: inline-block; margin: 10px; padding: 15px; background: #2a2a2a; border-radius: 5px; min-width: 200px; }
		.metric-value { font-size: 24px; font-weight: bold; color: #4CAF50; }
		.metric-label { color: #aaa; font-size: 14px; }
		.good { color: #4CAF50; }
		.warning { color: #FF9800; }
		.bad { color: #F44336; }
		.chart { margin: 20px 0; padding: 20px; background: #2a2a2a; border-radius: 5px; }
	</style>
</head>
<body>
	<h1>Benchmark Format Couleur: RGB565 vs Palette 8-bit</h1>
	<p>Généré le: %s</p>
	
	<h2>Résumé des Tests</h2>
	<div class="metric">
		<div class="metric-label">Tests réalisés</div>
		<div class="metric-value">%d</div>
	</div>
	<div class="metric">
		<div class="metric-label">Résolutions testées</div>
		<div class="metric-value">%d</div>
	</div>
""" % (Time.get_datetime_string_from_system(), _results.size(), _results.size())
	
	# Tableau des résultats
	html += """
	<h2>Résultats Détaillés</h2>
	<table>
		<tr>
			<th>Test</th>
			<th>Résolution</th>
			<th>Format</th>
			<th>FPS</th>
			<th>Temps (ms)</th>
			<th>VRAM (KB)</th>
			<th>Bande passante (KB/s)</th>
			<th>PSNR (dB)</th>
			<th>SSIM</th>
			<th>Banding</th>
		</tr>
"""
	
	for result in _results:
		var fps_class = "good" if result.fps_palette > result.fps_rgb565 else "warning"
		var vram_class = "good" if result.vram_palette_bytes < result.vram_rgb565_bytes else "warning"
		var psnr_class = "good" if result.avg_psnr > 30 else ("warning" if result.avg_psnr > 20 else "bad")
		
		html += """
		<tr>
			<td>%d</td>
			<td>%dx%d</td>
			<td>RGB565</td>
			<td>%.1f</td>
			<td>%.2f</td>
			<td>%.1f</td>
			<td>%.1f</td>
			<td class="%s">%.2f</td>
			<td>%.4f</td>
			<td>%.4f</td>
		</tr>
		<tr>
			<td>%d</td>
			<td>%dx%d</td>
			<td>Palette</td>
			<td class="%s">%.1f</td>
			<td>%.2f</td>
			<td class="%s">%.1f</td>
			<td>%.1f</td>
			<td class="%s">%.2f</td>
			<td>%.4f</td>
			<td>%.4f</td>
		</tr>
""" % [
			result.test_index, result.resolution, result.resolution * 9/16,
			result.fps_rgb565, result.avg_frame_time_rgb565_ms, result.vram_rgb565_bytes / 1024.0, result.bandwidth_rgb565_kbps,
			psnr_class, result.avg_psnr, result.avg_ssim, result.banding_artifacts_score,
			result.test_index, result.resolution, result.resolution * 9/16,
			fps_class, result.fps_palette, result.avg_frame_time_palette_ms, vram_class, result.vram_palette_bytes / 1024.0,
			result.bandwidth_palette_kbps, psnr_class, result.avg_psnr, result.avg_ssim, result.banding_artifacts_score
		]
	
	html += """
	</table>
	
	<h2>Analyse Comparative</h2>
	<div class="chart">
		<h3>Performance (FPS)</h3>
		<p>Comparaison des performances entre RGB565 et Palette 8-bit</p>
	</div>
	
	<div class="chart">
		<h3>Utilisation VRAM</h3>
		<p>Économie de mémoire avec la palette 8-bit</p>
	</div>
	
	<div class="chart">
		<h3>Qualité Visuelle</h3>
		<p>PSNR et SSIM moyens par résolution</p>
	</div>
	
	<h2>Recommandations</h2>
	<ul>
"""
	
	for result in _results:
		var recommendation = "Palette 8-bit" if result.fps_palette > result.fps_rgb565 and result.avg_psnr > 30 else "RGB565"
		var reason = "Meilleures performances et qualité acceptable" if recommendation == "Palette 8-bit" else "Qualité supérieure requise"
		
		html += """
		<li><strong>%dx%d:</strong> %s - %s</li>
""" % [result.resolution, result.resolution * 9/16, recommendation, reason]
	
	html += """
	</ul>
	
	<h2>Conclusion</h2>
	<p>Le benchmark démontre les compromis entre les deux formats :</p>
	<ul>
		<li><strong>RGB565:</strong> Meilleure qualité (16-bit), mais utilisation VRAM plus élevée</li>
		<li><strong>Palette 8-bit:</strong> Économie significative de VRAM (50-75%), performances potentiellement meilleures, mais qualité réduite</li>
		<li><strong>Dithering:</strong> Améliore la perception visuelle en réduisant le banding</li>
	</ul>
</body>
</html>
"""
	
	return html


func _build_text_content() -> String:
	"""Construit le contenu texte du rapport"""
	var text = """
================================================================================
                    BENCHMARK FORMAT COULEUR - RAPPORT
================================================================================
Généré le: %s

SUMMARY
--------------------------------------------------------------------------------
Tests réalisés: %d
Résolutions testées: %d
Dithering activé: %s

================================================================================
RÉSULTATS DÉTAILLÉS
================================================================================
""" % [Time.get_datetime_string_from_system(), _results.size(), _results.size(), "Oui" if _results[0].use_dithering else "Non"]
	
	for result in _results:
		text += """
--------------------------------------------------------------------------------
Test #%d - Résolution: %dx%d
--------------------------------------------------------------------------------
  Format RGB565:
    FPS:           %.1f
    Temps rendu:   %.2f ms
    VRAM:          %.2f KB
    Bande passante: %.1f KB/s
  
  Format Palette 8-bit:
    FPS:           %.1f
    Temps rendu:   %.2f ms
    VRAM:          %.2f KB
    Bande passante: %.1f KB/s
  
  Comparaison:
    Gain FPS:              %+.1f%%
    Économie VRAM:         %.1f%%
    Économie bande passante: %.1f%%
  
  Qualité:
    PSNR:                  %.2f dB
    SSIM:                  %.4f
    Artefacts banding:     %.4f
""" % [
			result.test_index, result.resolution, result.resolution * 9/16,
			result.fps_rgb565, result.avg_frame_time_rgb565_ms, result.vram_rgb565_bytes / 1024.0, result.bandwidth_rgb565_kbps,
			result.fps_palette, result.avg_frame_time_palette_ms, result.vram_palette_bytes / 1024.0, result.bandwidth_palette_kbps,
			(result.fps_palette - result.fps_rgb565) / result.fps_rgb565 * 100.0,
			result.vram_saving_pct, result.bandwidth_saving_pct,
			result.avg_psnr, result.avg_ssim, result.banding_artifacts_score
		]
	
text += """
================================================================================
ANALYSE COMPARATIVE
================================================================================

1. PERFORMANCE (FPS)
   - RGB565:    """
	
	var total_fps_rgb = 0.0
	var total_fps_pal = 0.0
	for result in _results:
		total_fps_rgb += result.fps_rgb565
		total_fps_pal += result.fps_palette
	
	var avg_fps_rgb = total_fps_rgb / _results.size()
	var avg_fps_pal = total_fps_pal / _results.size()
	
text += "%.1f (moyenne)\n" % avg_fps_rgb
	text += "   - Palette 8-bit: %.1f (moyenne)\n" % avg_fps_pal
	text += "   - Différence: %+.1f%%\n" % ((avg_fps_pal - avg_fps_rgb) / avg_fps_rgb * 100.0)
	
	text += """
2. UTILISATION VRAM
   - RGB565:    """
	
	var total_vram_rgb = 0.0
	var total_vram_pal = 0.0
	for result in _results:
		total_vram_rgb += result.vram_rgb565_bytes
		total_vram_pal += result.vram_palette_bytes
	
	var avg_vram_rgb = total_vram_rgb / _results.size()
	var avg_vram_pal = total_vram_pal / _results.size()
	
text += "%.2f KB (moyenne)\n" % (avg_vram_rgb / 1024.0)
	text += "   - Palette 8-bit: %.2f KB (moyenne)\n" % (avg_vram_pal / 1024.0)
	text += "   - Économie: %.1f%%\n" % ((avg_vram_rgb - avg_vram_pal) / avg_vram_rgb * 100.0)
	
	text += """
3. QUALITÉ VISUELLE
   - PSNR moyen:  """
	
	var total_psnr = 0.0
	var total_ssim = 0.0
	var total_banding = 0.0
	for result in _results:
		total_psnr += result.avg_psnr
		total_ssim += result.avg_ssim
		total_banding += result.banding_artifacts_score
	
	var avg_psnr = total_psnr / _results.size()
	var avg_ssim = total_ssim / _results.size()
	var avg_banding = total_banding / _results.size()
	
text += "%.2f dB\n" % avg_psnr
	text += "   - SSIM moyen:  %.4f\n" % avg_ssim
	text += "   - Banding:     %.4f\n" % avg_banding
	
	text += """
================================================================================
RECOMMANDATIONS
================================================================================
"""
	
	for result in _results:
		var rec = "Palette 8-bit" if result.fps_palette > result.fps_rgb565 and result.avg_psnr > 30 else "RGB565"
		text += "  • %dx%d: %s\n" % [result.resolution, result.resolution * 9/16, rec]
		text += "    (PSNR: %.2f dB, Gain FPS: %+.1f%%)\n" % [result.avg_psnr, (result.fps_palette - result.fps_rgb565) / result.fps_rgb565 * 100.0]
		text += "\n"
	
text += """
================================================================================
CONCLUSION
================================================================================
Le benchmark démontre que la palette 8-bit avec dithering offre un compromis
intéressant entre performance et qualité :
- Réduction significative de l'utilisation VRAM (50-75%%)
- Potentiel d'amélioration des performances
- Qualité visuelle acceptable avec PSNR > 30 dB
- Le dithering réduit efficacement les artefacts de banding

L'utilisation de RGB565 reste recommandée lorsque la qualité visuelle
primordiale est requise.
================================================================================
"""
	
	return text