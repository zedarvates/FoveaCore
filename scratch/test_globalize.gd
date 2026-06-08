extends SceneTree

func _init() -> void:
	var abs_path = "F:/video.mp4"
	var user_path = OS.get_user_data_dir() + "/fovea_preview.jpg"
	
	print("OS.get_user_data_dir(): ", OS.get_user_data_dir())
	print("globalize(abs_path): ", ProjectSettings.globalize_path(abs_path))
	print("globalize(user_path): ", ProjectSettings.globalize_path(user_path))
	quit()
