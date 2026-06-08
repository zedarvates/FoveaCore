extends SceneTree

func _init() -> void:
	var exported_count := 0
	var my_func = func():
		exported_count += 1
		print("Inside lambda: ", exported_count)
		
	my_func.call()
	my_func.call()
	print("Outside lambda: ", exported_count)
	quit()
