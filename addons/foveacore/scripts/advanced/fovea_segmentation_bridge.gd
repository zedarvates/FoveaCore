extends Resource
class_name FoveaSegmentationBridge

## FoveaSegmentationBridge — AI-driven 3D Gaussian Splat Segmentation
## Captures multi-view snapshots of splats, query SAM2/Vision LLMs,
## and back-projects 2D masks into 3D splat classifications.

@export var comfyui_url: String = "http://127.0.0.1:8188"
@export var sam_prompt: String = "clothing"
@export var threshold: float = 0.5
@export var resolution: int = 512
@export var use_simulation: bool = true

class ViewSnapshot extends RefCounted:
	var image: Image
	var camera_transform: Transform3D
	var fov: float
	var size: float
	var projection_type: Camera3D.ProjectionType
	var near: float
	var far: float
	var direction_name: String
	var mask_image: Image # Filled once received from API

## Segment a FoveaSplattable node and apply the resulting label to its splats
func segment_splattable(splattable: FoveaSplattable, label: String, callback: Callable) -> void:
	if splattable == null or splattable.loaded_splats.is_empty():
		push_error("FoveaSegmentationBridge: Splattable contains no splats to segment.")
		callback.call(false)
		return
		
	sam_prompt = label
	print("FoveaSegmentationBridge: Starting segmentation process for prompt: '", sam_prompt, "'")
	
	# Step 1: Capture snapshots from 6 orthographic/perspective directions
	var snapshots = await _capture_snapshots(splattable)
	if snapshots.is_empty():
		push_error("FoveaSegmentationBridge: Failed to capture snapshots.")
		callback.call(false)
		return
		
	# Step 2: Request 2D masks (either from AI server or via simulation fallback)
	if use_simulation:
		print("FoveaSegmentationBridge: Running in SIMULATION mode.")
		_simulate_masks(snapshots, splattable)
		_apply_backprojection(splattable, snapshots)
		callback.call(true)
	else:
		print("FoveaSegmentationBridge: Querying ComfyUI / AI Service...")
		_request_masks_async(snapshots, func(success: bool):
			if success:
				_apply_backprojection(splattable, snapshots)
				callback.call(true)
			else:
				push_warning("FoveaSegmentationBridge: AI service failed. Falling back to simulation.")
				_simulate_masks(snapshots, splattable)
				_apply_backprojection(splattable, snapshots)
				callback.call(true)
		)

## Capture snapshots from 6 standard directions around the splattable bounding box
func _capture_snapshots(splattable: FoveaSplattable) -> Array[ViewSnapshot]:
	var snapshots: Array[ViewSnapshot] = []
	
	# Calculate bounding box from loaded splats
	var min_pos = Vector3(INF, INF, INF)
	var max_pos = Vector3(-INF, -INF, -INF)
	for splat in splattable.loaded_splats:
		min_pos.x = min(min_pos.x, splat.position.x)
		min_pos.y = min(min_pos.y, splat.position.y)
		min_pos.z = min(min_pos.z, splat.position.z)
		max_pos.x = max(max_pos.x, splat.position.x)
		max_pos.y = max(max_pos.y, splat.position.y)
		max_pos.z = max(max_pos.z, splat.position.z)
	
	var aabb = AABB(min_pos, max_pos - min_pos)
	var center = splattable.global_transform * aabb.get_center()
	var diameter = aabb.size.length()
	if diameter < 0.1:
		diameter = 2.0
		
	# Define 6 viewing directions
	var directions = {
		"front": Vector3(0, 0, 1),
		"back": Vector3(0, 0, -1),
		"left": Vector3(-1, 0, 0),
		"right": Vector3(1, 0, 0),
		"top": Vector3(0, 1, 0),
		"bottom": Vector3(0, -1, 0)
	}
	
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return []
		
	# Create a temporary SubViewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(resolution, resolution)
	viewport.transparent_bg = true
	viewport.own_world_3d = false
	var splat_viewport = splattable.get_viewport()
	if splat_viewport:
		viewport.world_3d = splat_viewport.find_world_3d()
	tree.root.add_child(viewport)
	
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55.0
	camera.near = 0.05
	camera.far = diameter * 5.0
	viewport.add_child(camera)
	
	var dist = (diameter / 2.0) / sin(deg_to_rad(camera.fov / 2.0)) * 1.2
	
	for dir_name in directions:
		var dir_vec: Vector3 = directions[dir_name]
		var cam_pos = center + dir_vec * dist
		
		# Position camera and look at center
		camera.global_position = cam_pos
		var up_vec = Vector3.UP
		if abs(dir_vec.dot(Vector3.UP)) > 0.95:
			up_vec = Vector3.FORWARD
		camera.look_at(center, up_vec)
		
		# Wait for frame draw to capture Viewport texture
		if not use_simulation:
			await tree.process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
		
		var img = viewport.get_texture().get_image()
		if img == null or img.is_empty():
			if use_simulation:
				img = Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
			else:
				continue
			
		var snapshot = ViewSnapshot.new()
		snapshot.image = img
		snapshot.camera_transform = camera.global_transform
		snapshot.fov = camera.fov
		snapshot.size = camera.size
		snapshot.projection_type = camera.projection
		snapshot.near = camera.near
		snapshot.far = camera.far
		snapshot.direction_name = dir_name
		snapshots.append(snapshot)
		
	# Cleanup viewport
	viewport.queue_free()
	
	print("FoveaSegmentationBridge: Captured ", snapshots.size(), " snapshots successfully.")
	return snapshots

## Simulates 2D segmentation masks locally using smart spatial / color segmentation
func _simulate_masks(snapshots: Array[ViewSnapshot], splattable: FoveaSplattable) -> void:
	for snapshot in snapshots:
		var mask = Image.create(resolution, resolution, false, Image.FORMAT_L8)
		
		# Set up a temporary camera to project points and determine color/depth matches
		var camera = Camera3D.new()
		camera.transform = snapshot.camera_transform
		camera.projection = snapshot.projection_type
		camera.fov = snapshot.fov
		camera.size = snapshot.size
		camera.near = snapshot.near
		camera.far = snapshot.far
		
		# We need camera in the scene tree for unproject_position to work
		var tree = Engine.get_main_loop() as SceneTree
		tree.root.add_child(camera)
		
		for splat in splattable.loaded_splats:
			var world_pos = splattable.global_transform * splat.position
			if camera.is_position_behind(world_pos):
				continue
				
			var screen_pos = camera.unproject_position(world_pos)
			var px = int(screen_pos.x)
			var py = int(screen_pos.y)
			
			if px >= 0 and px < resolution and py >= 0 and py < resolution:
				# Apply a classification rule based on prompt
				var is_match = false
				
				if sam_prompt.containsn("cloth") or sam_prompt.containsn("drap"):
					# Cloth wrinkles tend to have high variation in normals and be in the upper/mid area
					var vertical_factor = clamp((world_pos.y - splattable.global_position.y) + 1.0, 0.0, 2.0) / 2.0
					var noise = sin(world_pos.x * 10.0) * cos(world_pos.z * 10.0)
					if vertical_factor > 0.4 and (abs(splat.normal.y) < 0.8 or noise > 0.1):
						is_match = true
						
				elif sam_prompt.containsn("liquid") or sam_prompt.containsn("water") or sam_prompt.containsn("eau"):
					# Liquids sit at the bottom or match bluish colors
					var is_blue = splat.color.b > 0.5 and splat.color.r < 0.6
					var is_bottom = world_pos.y - splattable.global_position.y < 0.3
					if is_blue or (is_bottom and splat.color.b > 0.3):
						is_match = true
						
				elif sam_prompt.containsn("wood") or sam_prompt.containsn("bois"):
					# Wood is brownish/yellowish
					var is_brown = splat.color.r > 0.4 and splat.color.g > 0.3 and splat.color.b < 0.3
					if is_brown:
						is_match = true
						
				elif sam_prompt.containsn("stone") or sam_prompt.containsn("pierre") or sam_prompt.containsn("brick") or sam_prompt.containsn("brique"):
					# Stone/bricks are grey or red/terracotta
					var is_grey = abs(splat.color.r - splat.color.g) < 0.1 and abs(splat.color.g - splat.color.b) < 0.1
					var is_brick_red = splat.color.r > 0.5 and splat.color.g < 0.4 and splat.color.b < 0.4
					if is_grey or is_brick_red:
						is_match = true
				else:
					# Default fallback: match everything above center
					if world_pos.y > splattable.global_position.y:
						is_match = true
						
				if is_match:
					mask.set_pixel(px, py, Color.WHITE)
					
		# Smooth out the simulated mask with a light dilation (to mock SAM behavior)
		mask = _dilate_mask(mask)
		snapshot.mask_image = mask
		camera.queue_free()

func _dilate_mask(img: Image) -> Image:
	var width = img.get_width()
	var height = img.get_height()
	var dilated = Image.create(width, height, false, Image.FORMAT_L8)
	
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if img.get_pixel(x, y).r > 0.5:
				dilated.set_pixel(x, y, Color.WHITE)
				# 4-way dilation
				dilated.set_pixel(x - 1, y, Color.WHITE)
				dilated.set_pixel(x + 1, y, Color.WHITE)
				dilated.set_pixel(x, y - 1, Color.WHITE)
				dilated.set_pixel(x, y + 1, Color.WHITE)
	return dilated

## Query the ComfyUI or local SAM2 server to obtain binary masks asynchronously
func _request_masks_async(snapshots: Array[ViewSnapshot], callback: Callable) -> void:
	# Keep track of completed snapshots
	var pending_count = snapshots.size()
	var failed = false
	
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		callback.call(false)
		return
		
	for snapshot in snapshots:
		var http_uploader = HTTPRequest.new()
		tree.root.add_child(http_uploader)
		
		# Upload snapshot
		var png_bytes = snapshot.image.save_png_to_buffer()
		var filename = "segment_" + snapshot.direction_name + "_" + str(Time.get_ticks_msec()) + ".png"
		var boundary = "FoveaBoundary" + str(Time.get_ticks_msec())
		
		var header_str = "--" + boundary + "\r\n"
		header_str += "Content-Disposition: form-data; name=\"image\"; filename=\"" + filename + "\"\r\n"
		header_str += "Content-Type: image/png\r\n\r\n"
		var footer_str = "\r\n--" + boundary + "--\r\n"
		
		var body = PackedByteArray()
		body.append_array(header_str.to_utf8_buffer())
		body.append_array(png_bytes)
		body.append_array(footer_str.to_utf8_buffer())
		
		var headers: Array[String] = [
			"Content-Type: multipart/form-data; boundary=" + boundary,
			"Content-Length: " + str(body.size())
		]
		
		http_uploader.request_completed.connect(
			func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
				http_uploader.queue_free()
				if response_code != 200 or failed:
					failed = true
					pending_count -= 1
					if pending_count == 0:
						callback.call(false)
					return
					
				var json = JSON.new()
				if json.parse(response_body.get_string_from_utf8()) != OK:
					failed = true
					pending_count -= 1
					if pending_count == 0:
						callback.call(false)
					return
					
				var response_dict: Dictionary = json.data
				var uploaded_name = response_dict.get("name", "")
				
				# Call segmentation pipeline
				_query_sam_segmentation(uploaded_name, snapshot, func(success: bool):
					pending_count -= 1
					if not success:
						failed = true
					if pending_count == 0:
						callback.call(not failed)
				)
		)
		
		var upload_url = comfyui_url + "/upload/image"
		var err = http_uploader.request_raw(upload_url, headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			http_uploader.queue_free()
			failed = true
			pending_count -= 1
			if pending_count == 0:
				callback.call(false)

func _query_sam_segmentation(image_name: String, snapshot: ViewSnapshot, callback: Callable) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var http_prompter = HTTPRequest.new()
	tree.root.add_child(http_prompter)
	
	# workflow payload using SAM and GroundingDINO
	var workflow: Dictionary = {
		"prompt": {
			"1": {
				"class_type": "LoadImage",
				"inputs": {
					"image": image_name
				}
			},
			"2": {
				"class_type": "GroundingDinoSAMSegment",
				"inputs": {
					"image": ["1", 0],
					"prompt": sam_prompt,
					"threshold": threshold
				}
			},
			"3": {
				"class_type": "SaveImage",
				"inputs": {
					"filename_prefix": "FoveaSegmentMask",
					"images": ["2", 0] # Returns the mask image
				}
			}
		}
	}
	
	var headers: Array[String] = ["Content-Type: application/json"]
	var body_str = JSON.stringify(workflow)
	
	http_prompter.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			http_prompter.queue_free()
			if response_code != 200:
				callback.call(false)
				return
				
			var json = JSON.new()
			if json.parse(response_body.get_string_from_utf8()) != OK:
				callback.call(false)
				return
				
			var response_dict: Dictionary = json.data
			var prompt_id = response_dict.get("prompt_id", "")
			if prompt_id.is_empty():
				callback.call(false)
				return
				
			# Poll for the output
			_poll_output_mask(prompt_id, snapshot, callback)
	)
	
	var err = http_prompter.request(comfyui_url + "/prompt", headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		http_prompter.queue_free()
		callback.call(false)

func _poll_output_mask(prompt_id: String, snapshot: ViewSnapshot, callback: Callable, attempt: int = 0) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if attempt > 30:
		callback.call(false)
		return
		
	await tree.create_timer(1.0).timeout
	
	var http_poller = HTTPRequest.new()
	tree.root.add_child(http_poller)
	
	http_poller.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			http_poller.queue_free()
			if response_code != 200:
				_poll_output_mask(prompt_id, snapshot, callback, attempt + 1)
				return
				
			var json = JSON.new()
			if json.parse(response_body.get_string_from_utf8()) != OK:
				_poll_output_mask(prompt_id, snapshot, callback, attempt + 1)
				return
				
			var history = json.data
			if not history.has(prompt_id):
				_poll_output_mask(prompt_id, snapshot, callback, attempt + 1)
				return
				
			var task_info = history[prompt_id]
			var outputs = task_info.get("outputs", {})
			if not outputs.has("3") or not outputs["3"].has("images") or outputs["3"]["images"].is_empty():
				callback.call(false)
				return
				
			var img_info = outputs["3"]["images"][0]
			var file_name = img_info.get("filename", "")
			var sub_dir = img_info.get("subfolder", "")
			var type = img_info.get("type", "output")
			
			# Download the mask image
			_download_mask(file_name, sub_dir, type, snapshot, callback)
	)
	
	var err = http_poller.request(comfyui_url + "/history/" + prompt_id)
	if err != OK:
		http_poller.queue_free()
		_poll_output_mask(prompt_id, snapshot, callback, attempt + 1)

func _download_mask(filename: String, subfolder: String, type: String, snapshot: ViewSnapshot, callback: Callable) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var http_downloader = HTTPRequest.new()
	tree.root.add_child(http_downloader)
	
	http_downloader.request_completed.connect(
		func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray):
			http_downloader.queue_free()
			if response_code != 200:
				callback.call(false)
				return
				
			var mask_img = Image.new()
			var err = mask_img.load_png_from_buffer(response_body)
			if err != OK:
				callback.call(false)
				return
				
			snapshot.mask_image = mask_img
			callback.call(true)
	)
	
	var query = "?filename=" + filename.uri_encode() + "&type=" + type.uri_encode()
	if not subfolder.is_empty():
		query += "&subfolder=" + subfolder.uri_encode()
		
	var err = http_downloader.request(comfyui_url + "/view" + query)
	if err != OK:
		http_downloader.queue_free()
		callback.call(false)

## Back-project 2D binary masks into the 3D Gaussian Splat cloud using camera projection matrices
func _apply_backprojection(splattable: FoveaSplattable, snapshots: Array[ViewSnapshot]) -> void:
	print("FoveaSegmentationBridge: Running 3D back-projection voting...")
	
	# Determine target layer based on prompt
	var target_layer = GaussianSplat.LayerType.BASE
	if sam_prompt.containsn("cloth") or sam_prompt.containsn("drap"):
		target_layer = GaussianSplat.LayerType.BASE # Or custom if dedicated layer added
	elif sam_prompt.containsn("liquid") or sam_prompt.containsn("water") or sam_prompt.containsn("eau"):
		target_layer = GaussianSplat.LayerType.LIQUID
	elif sam_prompt.containsn("saturation"):
		target_layer = GaussianSplat.LayerType.SATURATION
	elif sam_prompt.containsn("light"):
		target_layer = GaussianSplat.LayerType.LIGHT
	elif sam_prompt.containsn("shadow"):
		target_layer = GaussianSplat.LayerType.SHADOW
	
	# Initialize temporary cameras in scene tree to project points
	var tree = Engine.get_main_loop() as SceneTree
	var cameras: Array[Camera3D] = []
	for snapshot in snapshots:
		if snapshot.mask_image == null: continue
		var cam = Camera3D.new()
		cam.transform = snapshot.camera_transform
		cam.projection = snapshot.projection_type
		cam.fov = snapshot.fov
		cam.size = snapshot.size
		cam.near = snapshot.near
		cam.far = snapshot.far
		tree.root.add_child(cam)
		cameras.append(cam)
		
	var match_count = 0
	
	for splat in splattable.loaded_splats:
		var world_pos = splattable.global_transform * splat.position
		var yes_votes = 0
		var total_votes = 0
		
		for i in range(cameras.size()):
			var cam = cameras[i]
			var snapshot = snapshots[i]
			
			if cam.is_position_behind(world_pos):
				continue
				
			var screen_pos = cam.unproject_position(world_pos)
			var px = int(screen_pos.x)
			var py = int(screen_pos.y)
			
			if px >= 0 and px < resolution and py >= 0 and py < resolution:
				total_votes += 1
				var mask_val = snapshot.mask_image.get_pixel(px, py).r
				if mask_val > 0.5:
					yes_votes += 1
					
		# If the point was visible in at least one view, and more than 50% of views say yes:
		if total_votes > 0 and (float(yes_votes) / float(total_votes)) >= 0.5:
			splat.layer_type = target_layer
			
			# If liquid, we can customize parameters (viscosity, stiffness) dynamically
			if target_layer == GaussianSplat.LayerType.LIQUID:
				# Make liquids deformable by setting low stiffness in custom attributes if needed
				pass
			match_count += 1
			
	# Cleanup cameras
	for cam in cameras:
		cam.queue_free()
		
	print("FoveaSegmentationBridge: Back-projection completed. Segmented ", match_count, " splats as ", target_layer, ".")
