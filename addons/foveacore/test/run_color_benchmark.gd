# run_color_benchmark.gd
# Script principal d'exécution du benchmark de format couleur
# Orchestre l'exécution complète : tests unitaires, benchmark, génération de rapports

extends Node

# Références aux scripts
var _benchmark_script = preload("res://addons/foveacore/test/color_format_benchmark.gd")
var _test_script = preload("res://addons/foveacore/test/test_color_format_benchmark.gd")
var _report_script = preload("res://addons/foveacore/test/benchmark_report.gd")

# Nœuds
var _benchmark_node: Node = null
var _test_node: Node = null
var _report_node: Node = null

# État
var _state: String = "idle"  # idle, running_tests, running_benchmark, generating_report, complete
var _all_results: Dictionary = {}

signal execution_started()
signal tests_complete(passed: int, failed: int)
signal benchmark_complete(results: Array)
signal report_generated(path: String)
signal execution_complete(summary: Dictionary)


func _ready() -> void:
	print("\n" + "=".repeat(80))
	print("RunColorBenchmark: Démarrage de l'exécution complète")
	print("=".repeat(80))
	
	# Initialiser les nœuds
	_initialize_nodes()
	
	# Démarrer l'exécution
	execution_started.emit()
	_run_execution()


func _initialize_nodes() -> void:
	"""Initialise les nœuds nécessaires"""
	
	# Nœud benchmark
	_benchmark_node = _benchmark_script.new()
	_benchmark_node.name = "ColorBenchmark"
	add_child(_benchmark_node)
	_benchmark_node.benchmark_complete.connect(_on_benchmark_complete)
	
	# Nœud tests
	_test_node = _test_script.new()
	_test_node.name = "ColorTests"
	add_child(_test_node)
	_test_node.all_tests_complete.connect(_on_tests_complete)
	
	# Nœud rapport
	_report_node = _report_script.new()
	_report_node.name = "BenchmarkReport"
	add_child(_report_node)
	_report_node.report_generated.connect(_on_report_generated)


func _run_execution() -> void:
	"""Exécute la séquence complète"""
	_state = "running_tests"
	print("\n--- Phase 1: Tests Unitaires ---")
	
	# Attendre un frame pour que les nœuds soient prêts
	await get_tree().create_timer(0.5).timeout
	
	# Les tests démarrent automatiquement dans _ready()
	# On attend le signal de complétion


func _on_tests_complete(passed: int, failed: int) -> void:
	"""Appelé quand les tests unitaires sont terminés"""
	_all_results["unit_tests"] = {"passed": passed, "failed": failed}
	
	print("\n--- Phase 2: Benchmark Comparatif ---")
	_state = "running_benchmark"
	
	# Configurer et démarrer le benchmark
	_benchmark_node.test_duration = 5.0  # Tests plus courts pour la démo
	_benchmark_node.test_resolutions = [640, 1280]
	_benchmark_node.use_dithering = true
	_benchmark_node.save_results = true
	
	_benchmark_node.start_benchmark()


func _on_benchmark_complete(results: Array) -> void:
	"""Appelé quand le benchmark est terminé"""
	_all_results["benchmark"] = results
	
	print("\n--- Phase 3: Génération des Rapports ---")
	_state = "generating_report"
	
	# Générer les rapports
	_report_node.generate_report(results, "both")


func _on_report_generated(path: String) -> void:
	"""Appelé quand le rapport est généré"""
	print("\n--- Phase 4: Finalisation ---")
	_state = "complete"
	
	# Compiler le résumé
	var summary = _compile_summary()
	
	print("\n" + "=".repeat(80))
	print("RunColorBenchmark: Exécution terminée!")
	print("=".repeat(80))
	print("Résumé:")
	print("  Tests unitaires: %d réussis, %d échoués" % [
		summary.unit_tests_passed, summary.unit_tests_failed])
	print("  Benchmarks réalisés: %d" % summary.benchmark_count)
	print("  Rapports générés: %d" % summary.reports_generated)
	print("  Résolution recommandée: %s" % summary.recommended_resolution)
	print("  Format recommandé: %s" % summary.recommended_format)
	print("=".repeat(80))
	
	execution_complete.emit(summary)


func _compile_summary() -> Dictionary:
	"""Compile un résumé de l'exécution"""
	var summary = {
		"unit_tests_passed": _all_results.get("unit_tests", {}).get("passed", 0),
		"unit_tests_failed": _all_results.get("unit_tests", {}).get("failed", 0),
		"benchmark_count": 0,
		"reports_generated": 2,  # HTML et texte
		"recommended_resolution": "1280",
		"recommended_format": "RGB565"
	}
	
	var benchmark_results = _all_results.get("benchmark", [])
	summary["benchmark_count"] = benchmark_results.size()
	
	# Déterminer la recommandation basée sur les résultats
	if benchmark_results.size() > 0:
		var best_result = benchmark_results[0]
		for result in benchmark_results:
			# Préférer le format avec le meilleur compromis FPS/qualité
			if result.fps_palette > result.fps_rgb565 and result.avg_psnr > 30:
				summary["recommended_format"] = "Palette_8bit"
				best_result = result
		
		summary["recommended_resolution"] = str(best_result.resolution)
	
	return summary


# API publique
func run_full_execution() -> void:
	"""Démarre l'exécution complète"""
	if _state == "idle":
		_run_execution()
	else:
		push_warning("Exécution déjà en cours")


func get_state() -> String:
	"""Retourne l'état actuel"""
	return _state


func get_results() -> Dictionary:
	"""Retourne tous les résultats"""
	return _all_results.duplicate()