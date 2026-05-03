extends SceneTree

func _init():
	var arr = PackedByteArray()
	arr.resize(4)
	print("Methods of PackedByteArray:")
	for method in arr.get_method_list():
		if method.name.begins_with("encode"):
			print(" - ", method.name)
	quit()
