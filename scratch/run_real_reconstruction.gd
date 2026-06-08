extends SceneTree

func _init() -> void:
	print("==================================================")
	print("Starting Real Reconstruction Verification Run")
	print("==================================================")

	await create_timer(0.5).timeout

	# 1. Instantiate the Reconstruction Manager
	var manager = FoveaReconstructionManager.new()
	root.add_child(manager)

	# Ensure tools are checked
	var check_results = manager.check_tools()
	print("Tool verification: ", check_results)

	# 2. Create the reconstruction session
	var video_path = "F:/foveaengine/fovea-engine/Videos test/bonsaitree.mp4"
	var session_name = "bonsaitree_real_test"
	var session = manager.create_new_session(video_path, session_name)
	session.output_directory = "res://reconstructions/" + session_name
	session.dry_run = false
	session.mask_mode = "None" # Bypass the heavy masking process
	session.blur_threshold = 0.25 # Use the new lower threshold

	print("Session Configured:")
	print("  - Video: ", session.video_path)
	print("  - Output Dir: ", session.output_directory)
	print("  - Mask Mode: ", session.mask_mode)
	print("  - Blur Threshold: ", session.blur_threshold)

	# 3. Connect signals for visibility
	manager.session_progress_updated.connect(func(progress):
		print("  [PROGRESS] %.2f%% - Status: %s" % [progress, session.status])
	)
	manager.reconstruction_failed.connect(func(reason):
		print("  [FAILED] Reason: ", reason)
		quit(1)
	)
	manager.session_completed.connect(func(sess):
		print("  [COMPLETED] Reconstruction session finished successfully!")
		print("  Splat data path: ", sess.splat_data_path)
		quit(0)
	)
	manager.log_line_received.connect(func(line):
		print("  [LOG] ", line.strip_edges())
	)

	# 4. Start the reconstruction pipeline
	print("\nStarting pipeline execution...")
	manager.run_reconstruction(session)
