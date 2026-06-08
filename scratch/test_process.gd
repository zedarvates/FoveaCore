extends SceneTree

func _init() -> void:
	var pid_nonexistent = OS.create_process("nonexistent_command_xyz", [])
	print("Nonexistent command PID: ", pid_nonexistent)
	if pid_nonexistent != -1:
		print("Is nonexistent process running? ", OS.is_process_running(pid_nonexistent))
		
	var pid_ffmpeg = OS.create_process("ffmpeg", ["-version"])
	print("ffmpeg command PID: ", pid_ffmpeg)
	if pid_ffmpeg != -1:
		print("Is ffmpeg running immediately? ", OS.is_process_running(pid_ffmpeg))
		await create_timer(1.0).timeout
		print("Is ffmpeg running after 1s? ", OS.is_process_running(pid_ffmpeg))
		
	var ffmpeg_custom = "C:\\Users\\redga/Documents/ffmpeg-8.0-win-x64/ffmpeg.exe"
	var pid_ffmpeg_custom = OS.create_process(ffmpeg_custom, ["-version"])
	print("ffmpeg custom command PID: ", pid_ffmpeg_custom)
	if pid_ffmpeg_custom != -1:
		print("Is ffmpeg custom running immediately? ", OS.is_process_running(pid_ffmpeg_custom))
		await create_timer(1.0).timeout
		print("Is ffmpeg custom running after 1s? ", OS.is_process_running(pid_ffmpeg_custom))
		
	quit()
