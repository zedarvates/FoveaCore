extends Resource
class_name NeuralStyleBridge

## NeuralStyleBridge — Pont de connexion ComfyUI pour le stylisme de textures
## Permet d'envoyer des requêtes à une instance ComfyUI locale ou distante (port 8188)
## pour générer ou styliser des textures d'eau en Img2Img.

@export var comfyui_url: String = "http://127.0.0.1:8188"
@export var model_path: String = ""
@export var intensity: float = 0.55 # Denoise factor pour Img2Img
@export var output_resolution: Vector2i = Vector2i(512, 512)
@export var checkpoint_name: String = "v1-5-pruned-emaonly.safetensors"
@export var positive_prompt_suffix: String = "high quality, hyperrealistic water texture, ripple flow"
@export_multiline var negative_prompt: String = "blurry, low quality, bad details, text, watermark, signature"

# Instance to an external ONNX runtime (via Plugin or GDExtension)
var _inference_engine: Object = null

# Requêtes HTTP actives pour le suivi
var _active_http_requests: Array[HTTPRequest] = []

func load_style_model(path: String) -> bool:
	model_path = path
	if not FileAccess.file_exists(path):
		push_error("NeuralStyleBridge: Fichier de modèle introuvable à ", path)
		return false
	print("NeuralStyleBridge: Modèle LoRA/ONNX chargé : ", model_path)
	return true

## Méthode de secours synchrone simulée (existante)
func apply_style(source: Image) -> Image:
	var stylized := source.duplicate()
	stylized.adjust_bcs(1.2, 1.5, 0.8) # Simulation rapide
	print("NeuralStyleBridge: Frame stylisée (Simulation locale).")
	return stylized

func is_style_ready() -> bool:
	return not model_path.is_empty()

## --- PIPELINE ASYNCHRONE COMFYUI ---

## Déclenche le pipeline Img2Img asynchrone pour styliser une texture d'eau
func stylize_texture_comfy(input_image: Image, positive_prompt: String, callback: Callable) -> void:
	if input_image == null:
		push_error("NeuralStyleBridge: Image d'entrée nulle.")
		callback.call(null)
		return

	# Étape 1 : Sauvegarder l'image au format PNG en mémoire
	var prepared_image: Image = input_image.duplicate()
	prepared_image.resize(output_resolution.x, output_resolution.y)
	var png_bytes: PackedByteArray = prepared_image.save_png_to_buffer()
	if png_bytes.is_empty():
		push_error("NeuralStyleBridge: Échec de l'encodage de l'image en PNG.")
		callback.call(null)
		return

	# Étape 2 : Créer un client HTTP temporaire sur le Root de la scène pour l'asynchronisme
	var main_loop := Engine.get_main_loop()
	if not main_loop or not main_loop is SceneTree:
		push_error("NeuralStyleBridge: Impossible d'accéder au SceneTree.")
		callback.call(null)
		return

	var tree := main_loop as SceneTree
	var http_uploader := HTTPRequest.new()
	tree.root.add_child(http_uploader)
	_active_http_requests.append(http_uploader)

	var filename := "fovea_water_input_" + str(Time.get_ticks_msec()) + ".png"
	var boundary := "GodotBoundary" + str(Time.get_ticks_msec())
	
	# Construire le corps multipart/form-data pour l'upload d'image
	var header_str := "--" + boundary + "\r\n"
	header_str += "Content-Disposition: form-data; name=\"image\"; filename=\"" + filename + "\"\r\n"
	header_str += "Content-Type: image/png\r\n\r\n"
	var footer_str := "\r\n--" + boundary + "--\r\n"

	var body := PackedByteArray()
	body.append_array(header_str.to_utf8_buffer())
	body.append_array(png_bytes)
	body.append_array(footer_str.to_utf8_buffer())

	var headers: Array[String] = [
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"Content-Length: " + str(body.size())
	]

	# Connecter le callback de complétion de l'upload
	http_uploader.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			_cleanup_request(http_uploader)
			if response_code != 200:
				push_error("NeuralStyleBridge: Échec de l'upload d'image vers ComfyUI (Code: %d)." % response_code)
				callback.call(null)
				return

			var json_parser := JSON.new()
			if json_parser.parse(response_body.get_string_from_utf8()) != OK:
				push_error("NeuralStyleBridge: Erreur lors de l'analyse de la réponse d'upload.")
				callback.call(null)
				return

			var response_dict: Dictionary = json_parser.data
			var uploaded_name: String = response_dict.get("name", "")
			if uploaded_name.is_empty():
				push_error("NeuralStyleBridge: Nom de fichier manquant dans la réponse ComfyUI.")
				callback.call(null)
				return
				
			# Étape 3 : Soumettre le workflow avec le nom de l'image
			_submit_comfy_workflow(uploaded_name, positive_prompt, callback, tree)
	)

	var upload_url: String = _endpoint("/upload/image")
	var err := http_uploader.request_raw(upload_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("NeuralStyleBridge: Échec de la requête d'upload (Err: %d)." % err)
		_cleanup_request(http_uploader)
		callback.call(null)


## Soumet le workflow ComfyUI au serveur `/prompt`
func _submit_comfy_workflow(image_name: String, positive_prompt: String, callback: Callable, tree: SceneTree) -> void:
	var http_prompter := HTTPRequest.new()
	tree.root.add_child(http_prompter)
	_active_http_requests.append(http_prompter)

	var workflow: Dictionary = _build_img2img_workflow(image_name, positive_prompt)

	var headers: Array[String] = ["Content-Type: application/json"]
	var body_str: String = JSON.stringify(workflow)

	http_prompter.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			_cleanup_request(http_prompter)
			if response_code != 200:
				push_error("NeuralStyleBridge: Échec de la soumission du prompt à ComfyUI (Code: %d)." % response_code)
				callback.call(null)
				return

			var json_parser := JSON.new()
			if json_parser.parse(response_body.get_string_from_utf8()) != OK:
				push_error("NeuralStyleBridge: Erreur lors de l'analyse du prompt_id.")
				callback.call(null)
				return

			var response_dict: Dictionary = json_parser.data
			var prompt_id: String = response_dict.get("prompt_id", "")
			if prompt_id.is_empty():
				push_error("NeuralStyleBridge: Aucun prompt_id renvoyé par le serveur.")
				callback.call(null)
				return

			# Étape 4 : Lancer le polling de l'historique de rendu
			_poll_comfy_status(prompt_id, callback, tree)
	)

	var prompt_url: String = _endpoint("/prompt")
	var err: Error = http_prompter.request(prompt_url, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		push_error("NeuralStyleBridge: Échec de la requête prompt (Err: %d)." % err)
		_cleanup_request(http_prompter)
		callback.call(null)


## Construit le workflow Img2Img livré par défaut. Cette fonction pure est
## publique afin que les intégrations Godot puissent inspecter, adapter ou
## sérialiser le workflow avant de l'envoyer à une instance ComfyUI locale.
func build_img2img_workflow(image_name: String, positive_prompt: String, seed: int = -1) -> Dictionary:
	return _build_img2img_workflow(image_name, positive_prompt, seed)


func _build_img2img_workflow(image_name: String, prompt_text: String, seed: int = -1) -> Dictionary:
	var resolved_seed: int = seed if seed >= 0 else randi()
	var complete_prompt: String = prompt_text.strip_edges()
	if not positive_prompt_suffix.is_empty():
		if not complete_prompt.is_empty():
			complete_prompt += ", "
		complete_prompt += positive_prompt_suffix

	return {
		"prompt": {
			"3": {
				"class_type": "KSampler",
				"inputs": {
					"seed": resolved_seed,
					"steps": 20,
					"cfg": 7.0,
					"sampler_name": "euler",
					"scheduler": "normal",
					"denoise": intensity,
					"model": ["4", 0],
					"positive": ["5", 0],
					"negative": ["6", 0],
					"latent_image": ["10", 0]
				}
			},
			"4": {
				"class_type": "CheckpointLoaderSimple",
				"inputs": {
					"ckpt_name": checkpoint_name
				}
			},
			"5": {
				"class_type": "CLIPTextEncode",
				"inputs": {
					"text": complete_prompt,
					"clip": ["4", 1]
				}
			},
			"6": {
				"class_type": "CLIPTextEncode",
				"inputs": {
					"text": negative_prompt,
					"clip": ["4", 1]
				}
			},
			"8": {
				"class_type": "VAEDecode",
				"inputs": {
					"samples": ["3", 0],
					"vae": ["4", 2]
				}
			},
			"9": {
				"class_type": "SaveImage",
				"inputs": {
					"filename_prefix": "FoveaStylizedWater",
					"images": ["8", 0]
				}
			},
			"10": {
				"class_type": "VAEEncode",
				"inputs": {
					"pixels": ["11", 0],
					"vae": ["4", 2]
				}
			},
			"11": {
				"class_type": "LoadImage",
				"inputs": {
					"image": image_name,
					"upload": "image"
				}
			}
		}
	}


## Boucle de polling pour surveiller l'état de la tâche sur ComfyUI
func _poll_comfy_status(prompt_id: String, callback: Callable, tree: SceneTree, attempt: int = 0) -> void:
	if attempt > 45: # Timeout après 45 tentatives (~45 secondes)
		push_error("NeuralStyleBridge: Dépassement de délai (timeout) pour le rendu de texture.")
		callback.call(null)
		return

	# Attendre 1.0 seconde avant de sonder à nouveau
	await tree.create_timer(1.0).timeout

	var http_poller := HTTPRequest.new()
	tree.root.add_child(http_poller)
	_active_http_requests.append(http_poller)

	http_poller.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			_cleanup_request(http_poller)
			if response_code != 200:
				# Tâche peut être en cours, continuer de sonder
				_poll_comfy_status(prompt_id, callback, tree, attempt + 1)
				return
				
			var json_parser := JSON.new()
			if json_parser.parse(response_body.get_string_from_utf8()) != OK:
				_poll_comfy_status(prompt_id, callback, tree, attempt + 1)
				return
				
			var history_dict: Dictionary = json_parser.data
			if not history_dict.has(prompt_id):
				# Toujours en attente d'exécution dans la file d'attente
				_poll_comfy_status(prompt_id, callback, tree, attempt + 1)
				return
				
			# Rendu complété ! Récupérer la première image produite, sans supposer
			# que le workflow utilise l'identifiant de nœud historique "9".
			var task_info: Dictionary = history_dict[prompt_id]
			var image_info: Dictionary = find_first_output_image(task_info)
			if image_info.is_empty():
				push_error("NeuralStyleBridge: Rendu complété mais aucune image de sortie trouvée.")
				callback.call(null)
				return

			var generated_filename: String = image_info.get("filename", "")
			var subfolder: String = image_info.get("subfolder", "")
			var type: String = image_info.get("type", "output")
			
			if generated_filename.is_empty():
				push_error("NeuralStyleBridge: Nom d'image générée vide.")
				callback.call(null)
				return
				
			# Étape 5 : Télécharger l'image finale
			_download_stylized_image(generated_filename, subfolder, type, callback, tree)
	)

	var history_url: String = _endpoint("/history/" + prompt_id.uri_encode())
	var err := http_poller.request(history_url)
	if err != OK:
		_cleanup_request(http_poller)
		_poll_comfy_status(prompt_id, callback, tree, attempt + 1)


## Télécharge l'image générée depuis ComfyUI et la convertit en Image Godot
func _download_stylized_image(filename: String, subfolder: String, type: String, callback: Callable, tree: SceneTree) -> void:
	var http_downloader := HTTPRequest.new()
	tree.root.add_child(http_downloader)
	_active_http_requests.append(http_downloader)

	http_downloader.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			_cleanup_request(http_downloader)
			if response_code != 200:
				push_error("NeuralStyleBridge: Échec du téléchargement de la texture stylisée (Code: %d)." % response_code)
				callback.call(null)
				return
				
			var stylized_image := Image.new()
			var err := stylized_image.load_png_from_buffer(response_body)
			if err != OK:
				push_error("NeuralStyleBridge: Impossible de charger la texture PNG reçue (Err: %d)." % err)
				callback.call(null)
				return
				
			print("NeuralStyleBridge: Texture stylisée téléchargée et importée avec succès de ComfyUI !")
			callback.call(stylized_image)
	)

	var query_params := "?filename=" + filename.uri_encode()
	if not subfolder.is_empty():
		query_params += "&subfolder=" + subfolder.uri_encode()
	query_params += "&type=" + type.uri_encode()
	
	var download_url: String = _endpoint("/view") + query_params
	var err := http_downloader.request(download_url)
	if err != OK:
		push_error("NeuralStyleBridge: Échec de la requête de téléchargement (Err: %d)." % err)
		_cleanup_request(http_downloader)
		callback.call(null)


## Nettoie et supprime l'instance de requête HTTP du Root
func _cleanup_request(http_node: HTTPRequest) -> void:
	if http_node == null:
		return
	if http_node.is_inside_tree():
		http_node.get_parent().remove_child(http_node)
	http_node.queue_free()
	_active_http_requests.erase(http_node)


## Extrait la première image déclarée par un nœud de sortie ComfyUI. Les IDs
## de nœuds sont propres à chaque workflow, notamment pour les graphes 3DGS.
func find_first_output_image(history_entry: Dictionary) -> Dictionary:
	var outputs: Dictionary = history_entry.get("outputs", {})
	var node_ids: Array = outputs.keys()
	node_ids.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
	for node_id: Variant in node_ids:
		var node_output: Variant = outputs[node_id]
		if not node_output is Dictionary:
			continue
		var node_output_dict: Dictionary = node_output
		var images: Variant = node_output_dict.get("images", [])
		if not images is Array or images.is_empty():
			continue
		var first_image: Variant = images[0]
		if first_image is Dictionary:
			var first_image_dict: Dictionary = first_image
			if not str(first_image_dict.get("filename", "")).is_empty():
				return first_image_dict.duplicate(true)
	return {}


func _endpoint(path: String) -> String:
	return comfyui_url.trim_suffix("/") + path
