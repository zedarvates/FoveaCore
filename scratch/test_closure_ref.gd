extends SceneTree

func _init() -> void:
	var counter = [0]
	var my_func = func():
		counter[0] += 1
		print("Inside lambda: ", counter[0])
		
	my_func.call()
	my_func.call()
	print("Outside lambda: ", counter[0])
	quit()
