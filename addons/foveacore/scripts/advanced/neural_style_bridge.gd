extends Resource
class_name NeuralStyleBridge

## NeuralStyleBridge — ComfyUI bridge for photorealistic Img2Img generation.
## Sends source images to a local or remote ComfyUI instance and
## preserves source structure while restoring natural material detail.

@export var comfyui_url: String = "http://127.0.0.1:8188"
@export var comfyui_fallback_urls: PackedStringArray = PackedStringArray(["http://127.0.0.1:8000"])
@export var model_path: String = ""
## Low-detail splat previews need a decisive Img2Img pass; weaker values retain
## their blurred blobs and synthetic colour cast instead of rebuilding detail.
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.85
@export var output_resolution: Vector2i = Vector2i(1024, 1024)
## Empty means: query ComfyUI and select a known photorealistic checkpoint.
## An explicit value remains an opt-in override, but must exist on the server.
@export var checkpoint_name: String = ""
@export_range(1, 100, 1) var sampling_steps: int = 50
@export_range(1.0, 30.0, 0.1) var guidance_scale: float = 6.5
@export_enum("euler", "euler_ancestral", "dpmpp_2m", "dpmpp_2m_sde") var sampler_name: String = "dpmpp_2m"
@export_enum("normal", "karras", "exponential", "sgm_uniform") var scheduler_name: String = "karras"
@export var positive_prompt_suffix: String = "photorealistic photograph, true-to-life natural colors, natural materials, physically accurate lighting, realistic fine details, sharp focus, high dynamic range, high quality"
@export_multiline var negative_prompt: String = "cartoon, illustration, childlike drawing, painting, anime, low-poly, plastic, glowing foliage, neon colors, oversaturated, cyan color cast, oversmoothed, blurry, low resolution, compression artifacts, blocky details, bad details, text, watermark, signature"

# GDScript does not treat the implicit conversion to Array[String] as a
# constant expression during editor class registration. Keep the immutable
# literal untyped here; every consumer still iterates it as String.
const PHOTOREALISTIC_CHECKPOINT_HINTS: Array = [
	"juggernaut",
	"realvisxl",
	"realisticvision",
	"epicrealism",
	"photoreal",
	"realistic",
	"sdxl_base",
	"sd_xl_base",
	"sdxl"
]

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

## Conservative synchronous fallback: never fake photorealism with a color
## filter when no inference model is available.
func apply_style(source: Image) -> Image:
	var preserved: Image = source.duplicate()
	push_warning("NeuralStyleBridge: aucun modèle d'inférence actif; image source préservée sans stylisation.")
	return preserved

func is_style_ready() -> bool:
	return not model_path.is_empty()

## --- PIPELINE ASYNCHRONE COMFYUI ---

## Starts the asynchronous photorealistic Img2Img pipeline.
func stylize_texture_comfy(input_image: Image, positive_prompt: String, callback: Callable) -> void:
	if input_image == null:
		push_error("NeuralStyleBridge: Image d'entrée nulle.")
		callback.call(null)
		return

	var main_loop: MainLoop = Engine.get_main_loop()
	if not main_loop is SceneTree:
		push_error("NeuralStyleBridge: Impossible d'accéder au SceneTree.")
		callback.call(null)
		return

	var tree: SceneTree = main_loop as SceneTree
	_resolve_comfyui_checkpoint(
		tree,
		func(resolved_checkpoint: String) -> void:
			if resolved_checkpoint.is_empty():
				callback.call(null)
				return
			checkpoint_name = resolved_checkpoint
			_upload_photorealistic_input(input_image, positive_prompt, callback, tree)
	)


func _upload_photorealistic_input(input_image: Image, positive_prompt: String, callback: Callable, tree: SceneTree) -> void:
	# Lanczos avoids adding bilinear blur before the Img2Img pass.
	var prepared_image: Image = input_image.duplicate()
	prepared_image.resize(output_resolution.x, output_resolution.y, Image.INTERPOLATE_LANCZOS)
	var png_bytes: PackedByteArray = prepared_image.save_png_to_buffer()
	if png_bytes.is_empty():
		push_error("NeuralStyleBridge: Échec de l'encodage de l'image en PNG.")
		callback.call(null)
		return

	var http_uploader: HTTPRequest = HTTPRequest.new()
	tree.root.add_child(http_uploader)
	_active_http_requests.append(http_uploader)

	var filename: String = "fovea_photoreal_input_" + str(Time.get_ticks_msec()) + ".png"
	var boundary: String = "GodotBoundary" + str(Time.get_ticks_msec())
	
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


## Queries configured local endpoints and resolves a checkpoint before upload.
## This prevents a missing or illustration-oriented legacy default from being
## submitted silently as a supposedly photorealistic generation.
func _resolve_comfyui_checkpoint(tree: SceneTree, callback: Callable, candidate_index: int = 0, saw_server: bool = false) -> void:
	var candidates: Array[String] = get_comfyui_endpoint_candidates()
	if candidate_index >= candidates.size():
		if saw_server:
			push_error("NeuralStyleBridge: aucun checkpoint photoréaliste compatible n'est installé dans ComfyUI.")
		else:
			push_error("NeuralStyleBridge: aucune instance ComfyUI joignable sur les endpoints configurés.")
		callback.call("")
		return

	var candidate_url: String = candidates[candidate_index]
	var http_preflight: HTTPRequest = HTTPRequest.new()
	tree.root.add_child(http_preflight)
	_active_http_requests.append(http_preflight)
	http_preflight.request_completed.connect(
		func(_result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
			_cleanup_request(http_preflight)
			if response_code != 200:
				_resolve_comfyui_checkpoint(tree, callback, candidate_index + 1, saw_server)
				return

			var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
			if not parsed is Dictionary:
				_resolve_comfyui_checkpoint(tree, callback, candidate_index + 1, true)
				return

			var available: PackedStringArray = extract_available_checkpoints(parsed as Dictionary)
			var resolved: String = select_photorealistic_checkpoint(available)
			if resolved.is_empty():
				_resolve_comfyui_checkpoint(tree, callback, candidate_index + 1, true)
				return

			comfyui_url = candidate_url
			callback.call(resolved)
	)

	var request_error: Error = http_preflight.request(candidate_url.trim_suffix("/") + "/object_info/CheckpointLoaderSimple")
	if request_error != OK:
		_cleanup_request(http_preflight)
		_resolve_comfyui_checkpoint(tree, callback, candidate_index + 1, saw_server)


func get_comfyui_endpoint_candidates() -> Array[String]:
	var candidates: Array[String] = []
	var configured: Array[String] = [comfyui_url]
	for fallback_url: String in comfyui_fallback_urls:
		configured.append(fallback_url)
	for url: String in configured:
		var normalized: String = url.strip_edges().trim_suffix("/")
		if not normalized.is_empty() and not candidates.has(normalized):
			candidates.append(normalized)
	return candidates


func extract_available_checkpoints(object_info: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var loader_info: Variant = object_info.get("CheckpointLoaderSimple", {})
	if not loader_info is Dictionary:
		return result
	var input_info: Variant = (loader_info as Dictionary).get("input", {})
	if not input_info is Dictionary:
		return result
	var required_info: Variant = (input_info as Dictionary).get("required", {})
	if not required_info is Dictionary:
		return result
	var checkpoint_spec: Variant = (required_info as Dictionary).get("ckpt_name", [])
	if not checkpoint_spec is Array or checkpoint_spec.is_empty():
		return result
	var names: Variant = checkpoint_spec[0]
	if not names is Array:
		return result
	for name: Variant in names:
		var checkpoint: String = str(name).strip_edges()
		if not checkpoint.is_empty():
			result.append(checkpoint)
	return result


func select_photorealistic_checkpoint(available: PackedStringArray) -> String:
	var requested: String = checkpoint_name.strip_edges()
	if not requested.is_empty():
		for checkpoint: String in available:
			if checkpoint.to_lower() == requested.to_lower():
				return checkpoint
		return ""

	for hint: String in PHOTOREALISTIC_CHECKPOINT_HINTS:
		for checkpoint: String in available:
			var normalized: String = checkpoint.to_lower().replace("-", "_").replace(" ", "_")
			if normalized.contains(hint):
				return checkpoint
	return ""


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
	if checkpoint_name.strip_edges().is_empty():
		push_error("NeuralStyleBridge: le checkpoint doit être résolu avant de construire le workflow.")
		return {}
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
					"steps": sampling_steps,
					"cfg": guidance_scale,
					"sampler_name": sampler_name,
					"scheduler": scheduler_name,
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
					"filename_prefix": "FoveaPhotorealistic",
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
	if attempt > 180: # Allow up to three minutes for a 1024px quality pass.
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
