# ============================================================================
# FoveaEngine : studio_dependency_checker.gd
# Validation des pré-requis système pour le pipeline de Reconstruction
# ============================================================================

extends Node
class_name StudioDependencyChecker

signal check_completed(all_found: bool, results: Dictionary)

static var _wm2_cache: int = -1  # -1=unchecked, 0=not ready, 1=ready

## Lance une vérification asynchrone des outils requis
func check_all_tools() -> void:
	print("FoveaEngine [StudioTo3D] : Vérification des dépendances système...")

	var results = {
		"ffmpeg": _is_command_available("ffmpeg", ["-version"]),
		"colmap": _is_command_available("colmap", ["--help"]),
		"python": _is_command_available("python", ["--version"]),
		"worldmirror2": is_worldmirror2_ready()
	}

	var legacy_ok = results["ffmpeg"] and results["colmap"] and results["python"]
	var worldmirror_ok = results["ffmpeg"] and results["python"] and results["worldmirror2"]

	if worldmirror_ok:
		print("FoveaEngine [StudioTo3D] : [OK] WorldMirror 2.0 pret (reconstruction rapide ~10s).")
	elif legacy_ok:
		print("FoveaEngine [StudioTo3D] : [OK] Toutes les dependances legacy sont installees.")
		print("FoveaEngine [StudioTo3D] : (i) WorldMirror 2.0 non disponible. Reconstruction rapide desactivee (COLMAP uniquement).")
	else:
		printerr("FoveaEngine [StudioTo3D] : [FAIL] Dependances manquantes !")
		if not results["ffmpeg"]: printerr(" -> FFmpeg est introuvable dans le PATH.")
		if not results["colmap"]: printerr(" -> COLMAP est introuvable dans le PATH.")
		if not results["python"]: printerr(" -> Python est introuvable dans le PATH.")
		if not results["worldmirror2"]: printerr(" -> WorldMirror 2.0 (hyworld2) non installé.")

	check_completed.emit(legacy_ok or worldmirror_ok, results)

## Tente d'exécuter une commande et vérifie son code de retour
func _is_command_available(cmd: String, args: PackedStringArray) -> bool:
	var output = []
	var exit_code = OS.execute(cmd, args, output, false, false)
	return exit_code == 0

## Vérifie si WorldMirror 2.0 (hyworld2) est installé (static cache)
static func is_worldmirror2_ready() -> bool:
	if _wm2_cache != -1:
		return _wm2_cache == 1
	var output = []
	var script = "-c"
	var code = "import hyworld2.worldrecon.pipeline; print('OK')"
	var exit_code = OS.execute("python", [script, code], output, false, false)
	_wm2_cache = 1 if exit_code == 0 else 0
	return _wm2_cache == 1

## Retourne un texte formaté pour l'interface utilisateur
func get_diagnostic_text(results: Dictionary) -> String:
	var text = "Diagnostic Système :\n"
	text += "FFmpeg (Extraction video)        : " + ("[OK]" if results["ffmpeg"] else "[MISSING]") + "\n"
	text += "COLMAP (Structure from Motion)   : " + ("[OK]" if results["colmap"] else "[MISSING]") + "\n"
	text += "Python (3DGS Training)           : " + ("[OK]" if results["python"] else "[MISSING]") + "\n"
	text += "WorldMirror 2.0 (Reconstruction) : " + ("[OK] (reco rapide ~10s)" if results["worldmirror2"] else "[ ] Non installe (COLMAP uniquement)") + "\n"

	if not (results["ffmpeg"] and results["python"]):
		text += "\nVeuillez installer les outils manquants et les ajouter à votre variable d'environnement PATH système."
	elif not results["worldmirror2"]:
		text += "\n[INFO] Installez WorldMirror 2.0 pour une reconstruction 100x plus rapide :"
		text += "\n   pip install torch torchvision && git clone https://github.com/Tencent-Hunyuan/HY-World-2.0"

	return text
