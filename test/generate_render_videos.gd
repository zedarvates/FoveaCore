extends Node3D

## Script de Test Automatisé — Génération de Vidéos de Rendu de Splats
## Charge demo_bonsai.ply, applique les 6 styles visuels, et compile en MP4 via FFmpeg.
## Effectue également une reconstruction en mode dry-run pour la vidéo drone extérieure.

const SAVE_DIR := "res://reconstructions/rendering_test"
const FRAMES_DIR := "res://reconstructions/rendering_test/frames"
const BONSAI_PLY := "res://test/demo_bonsai.ply"
const DRONE_VIDEO := "res://Videos test/TreeTest1video360.mp4"

var camera: Camera3D
var splat_node: FoveaSplattable
var light: DirectionalLight3D
var world_env: WorldEnvironment

func _ready() -> void:
	print("[SplatTest] Démarrage du système de test de rendu et génération de vidéos...")
	
	# 1. Préparer les répertoires
	_setup_directories()
	
	# 2. Configurer la scène 3D
	_setup_scene()
	
	# 3. Lancer la simulation de reconstruction de la vidéo drone (Dry Run)
	await _run_drone_reconstruction_dry_run()
	
	# 4. Charger le Bonsaï pour les tests de styles artistiques
	await _load_bonsai_splats()
	
	# 5. Boucler sur les 6 styles artistiques et générer les vidéos
	var styles = ["Realistic", "Oil", "Watercolor", "Crosshatch", "Cartoon", "Pixelated"]
	for style in styles:
		await _render_and_compile_style(style)
		
	print("[SplatTest] ✅ Tous les tests de rendu et génération de vidéos sont terminés !")
	get_tree().quit(0)

func _setup_directories() -> void:
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(SAVE_DIR):
		dir.make_dir_recursive(SAVE_DIR)
	if not dir.dir_exists(FRAMES_DIR):
		dir.make_dir_recursive(FRAMES_DIR)

func _setup_scene() -> void:
	# Environnement
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	world_env.environment = env
	add_child(world_env)
	
	# Lumière
	light = DirectionalLight3D.new()
	light.position = Vector3(0, 5, 0)
	light.rotation_degrees = Vector3(-45, 0, 0)
	light.light_energy = 1.2
	add_child(light)
	
	# Caméra orientée vers le centre (0, 1, 0)
	camera = Camera3D.new()
	camera.position = Vector3(0, 2.5, 4.0)
	camera.rotation_degrees = Vector3(-15, 0, 0)
	add_child(camera)

func _load_bonsai_splats() -> void:
	print("[SplatTest] Chargement des splats du Bonsaï...")
	splat_node = FoveaSplattable.new()
	splat_node.name = "Splat_Bonsai"
	splat_node.splat_file_path = BONSAI_PLY
	splat_node.position = Vector3(0, 0.8, 0)
	add_child(splat_node)
	
	# Attendre le chargement
	await get_tree().create_timer(1.5).timeout

func _run_drone_reconstruction_dry_run() -> void:
	print("[SplatTest] Démarrage de la reconstruction dry-run sur la vidéo drone : ", DRONE_VIDEO)
	var global_video = ProjectSettings.globalize_path(DRONE_VIDEO)
	if not FileAccess.file_exists(global_video):
		print("[SplatTest] WARNING: Vidéo drone introuvable à : ", global_video)
		return
		
	var manager := FoveaReconstructionManager.new()
	add_child(manager)
	
	var session := manager.create_new_session(global_video, "drone_reconstruction_test")
	session.dry_run = true
	session.use_fast_sync = true # Mode STAR-Lite
	
	print("[SplatTest] Session créée : ", session.session_name)
	await manager.run_reconstruction(session)
	print("[SplatTest] Reconstruction dry-run terminée. Status de la session : ", session.status)
	manager.queue_free()

func _render_and_compile_style(style_name: String) -> void:
	print("[SplatTest] Génération des frames pour le style : ", style_name)
	
	# Chercher le renderer dans le splat_node ou globalement dans FoveaCoreManager
	var renderer = splat_node.find_child("SplatRenderer", true, false)
	if not renderer:
		renderer = splat_node.find_child("FoveaCoreSplatRenderer", true, false)
	if not renderer:
		var manager = get_node_or_null("/root/FoveaCoreManager")
		if manager:
			renderer = manager.get_node_or_null("FoveaCoreSplatRenderer")
		
	if not renderer:
		print("[SplatTest] ERROR: Aucun renderer trouvé.")
		return
		
	# Configurer le matériau et le shader selon le style
	var mat: ShaderMaterial = renderer.get("material_override")
	if not mat:
		mat = ShaderMaterial.new()
		renderer.set("material_override", mat)
		
	var mode_idx := 0
	match style_name:
		"Realistic": mode_idx = 0
		"Oil": mode_idx = 1
		"Watercolor": mode_idx = 2
		"Crosshatch": mode_idx = 3
		"Cartoon": mode_idx = 4
		"Pixelated": mode_idx = 5
		
	if mode_idx > 0:
		mat.shader = load("res://addons/foveacore/shaders/splat_render_artistic.gdshader")
		mat.set_shader_parameter("art_mode", mode_idx)
		var TexturedSplatGeneratorScript = load("res://addons/foveacore/scripts/advanced/textured_splat_generator.gd")
		if TexturedSplatGeneratorScript:
			TexturedSplatGeneratorScript.apply_brush_textures(mat)
	else:
		mat.shader = load("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
		
	# Ajuster le vent pour ajouter du dynamisme
	mat.set_shader_parameter("enable_wind", true)
	mat.set_shader_parameter("wind_speed", 1.5)
	mat.set_shader_parameter("wind_strength", 0.08)
	
	# Attendre 1 frame pour l'application du matériau
	await get_tree().process_frame
	
	# 60 frames = orbite complète (6 degrés par frame)
	var total_frames := 60
	var center := Vector3(0, 0.8, 0)
	var radius := 4.2
	
	# Nettoyer d'abord les anciennes frames du dossier temporaire
	_clean_frames_dir()
	
	for i in range(total_frames):
		var angle := deg_to_rad(i * (360.0 / total_frames))
		# Calcul de la position circulaire
		var cam_pos = center + Vector3(sin(angle) * radius, 1.2, cos(angle) * radius)
		camera.global_position = cam_pos
		camera.look_at(center, Vector3.UP)
		
		# Attendre le rendu de la frame
		await get_tree().process_frame
		await get_tree().process_frame # Double buffer sync
		
		# Capturer et sauvegarder l'image
		var img := get_viewport().get_texture().get_image()
		var frame_path := FRAMES_DIR.path_join("frame_%04d.png" % i)
		img.save_png(frame_path)
		
	# Compiler les frames en vidéo avec FFmpeg
	print("[SplatTest] Compilation de la vidéo pour ", style_name, "...")
	var video_path = SAVE_DIR.path_join("bonsai_%s.mp4" % style_name.to_lower())
	var global_video_path = ProjectSettings.globalize_path(video_path)
	var global_frames_pattern = ProjectSettings.globalize_path(FRAMES_DIR.path_join("frame_%04d.png"))
	
	var ffmpeg_args = [
		"-y",
		"-framerate", "30",
		"-i", global_frames_pattern,
		"-c:v", "libx264",
		"-pix_fmt", "yuv420p",
		global_video_path
	]
	
	var output = []
	var exit_code = OS.execute("ffmpeg", ffmpeg_args, output)
	if exit_code == 0:
		print("[SplatTest] ✅ Vidéo générée avec succès : ", video_path)
	else:
		print("[SplatTest] ❌ Échec de la compilation de la vidéo avec FFmpeg. Code sortie : ", exit_code)
		print("[SplatTest] FFmpeg Output: ", output)
		
	# Nettoyer les frames temporaires
	_clean_frames_dir()

func _clean_frames_dir() -> void:
	var dir = DirAccess.open(FRAMES_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".png"):
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
