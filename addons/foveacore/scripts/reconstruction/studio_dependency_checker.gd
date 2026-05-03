# ============================================================================
# FoveaEngine : studio_dependency_checker.gd
# Validation des pré-requis système pour le pipeline de Reconstruction
# ============================================================================

extends Node
class_name StudioDependencyChecker

signal check_completed(all_found: bool, results: Dictionary)

static var _wm2_cache: int = -1  # -1=unchecked, 0=not ready, 1=ready

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

func _check_worldmirror2_available() -> bool:
	return is_worldmirror2_ready()

func is_worldmirror2_ready_instance() -> bool:
	return is_worldmirror2_ready()

## Retourne un texte formaté pour l'interface utilisateur
func get_diagnostic_text(results: Dictionary) -> String:
    var text = "Diagnostic Système :\n"
    text += "FFmpeg (Extraction vidéo)        : " + ("✅ OK" if results["ffmpeg"] else "❌ MANQUANT") + "\n"
    text += "COLMAP (Structure from Motion)   : " + ("✅ OK" if results["colmap"] else "❌ MANQUANT") + "\n"
    text += "Python (3DGS Training)           : " + ("✅ OK" if results["python"] else "❌ MANQUANT") + "\n"
    text += "WorldMirror 2.0 (Reconstruction) : " + ("✅ OK (reco rapide ~10s)" if results["worldmirror2"] else "⚠ Non installé (COLMAP uniquement)") + "\n"
    
    if not (results["ffmpeg"] and results["python"]):
        text += "\nVeuillez installer les outils manquants et les ajouter à votre variable d'environnement PATH système."
    elif not results["worldmirror2"]:
        text += "\n💡 Installez WorldMirror 2.0 pour une reconstruction 100x plus rapide :"
        text += "\n   pip install torch torchvision && git clone https://github.com/Tencent-Hunyuan/HY-World-2.0"
        
    return text