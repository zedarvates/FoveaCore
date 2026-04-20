# ============================================================================
# FoveaEngine : studio_dependency_checker.gd
# Validation des pré-requis système pour le pipeline de Reconstruction
# ============================================================================

extends Node
class_name StudioDependencyChecker

signal check_completed(all_found: bool, results: Dictionary)

## Lance une vérification asynchrone des outils requis
func check_all_tools() -> void:
    print("FoveaEngine [StudioTo3D] : Vérification des dépendances système...")
    
    var results = {
        "ffmpeg": _is_command_available("ffmpeg", ["-version"]),
        "colmap": _is_command_available("colmap", ["help"]),
        "python": _is_command_available("python", ["--version"])
    }
    
    var all_found = results["ffmpeg"] and results["colmap"] and results["python"]
    
    if all_found:
        print("FoveaEngine [StudioTo3D] : ✅ Toutes les dépendances sont installées.")
    else:
        printerr("FoveaEngine [StudioTo3D] : ❌ Dépendances manquantes !")
        if not results["ffmpeg"]: printerr(" -> FFmpeg est introuvable dans le PATH.")
        if not results["colmap"]: printerr(" -> COLMAP est introuvable dans le PATH.")
        if not results["python"]: printerr(" -> Python est introuvable dans le PATH.")
        
    check_completed.emit(all_found, results)

## Tente d'exécuter une commande et vérifie son code de retour
func _is_command_available(cmd: String, args: PackedStringArray) -> bool:
    var output = []
    # OS.execute bloque le thread, mais pour un simple -version, c'est quasi instantané (< 10ms)
    var exit_code = OS.execute(cmd, args, output, true, true)
    
    # Certains outils retournent 1 pour 'help', on accepte 0 ou 1 si la commande a été trouvée
    if exit_code == 0 or exit_code == 1:
        return true
        
    return false

## Retourne un texte formaté pour l'interface utilisateur
func get_diagnostic_text(results: Dictionary) -> String:
    var text = "Diagnostic Système :\n"
    text += "FFmpeg (Extraction vidéo) : " + ("✅ OK" if results["ffmpeg"] else "❌ MANQUANT") + "\n"
    text += "COLMAP (Structure from Motion) : " + ("✅ OK" if results["colmap"] else "❌ MANQUANT") + "\n"
    text += "Python (3DGS Training) : " + ("✅ OK" if results["python"] else "❌ MANQUANT") + "\n"
    
    if not (results["ffmpeg"] and results["colmap"] and results["python"]):
        text += "\nVeuillez installer les outils manquants et les ajouter à votre variable d'environnement PATH système."
        
    return text