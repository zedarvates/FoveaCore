extends SceneTree

## Unit tests for StudioTo3D Pipeline (Dry Run mode)
## Validates: Workspace setup, Dry Run mode, JSON save/load, phase progress transitions

var _passed := 0
var _failed := 0
var _manager: FoveaReconstructionManager = null
var _session: ReconstructionSession = null
var _completed := false

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("StudioTo3D Pipeline Dry Run Integration Tests")
	print("=".repeat(70))

	# Wait a short moment to ensure the environment is ready
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# 1. Instantiate the manager and add to root
	_manager = FoveaReconstructionManager.new()
	root.add_child(_manager)
	
	# Make sure the manager created its components
	_assert("Processor created", _manager.processor != null)
	_assert("Exporter created", _manager.exporter != null)
	_assert("Backend created", _manager.backend != null)

	# Test de SplatProcessorHelper (Tagging, Shapes, Decimation)
	print("\nRunning SplatProcessorHelper tests...")
	var helper_script = load("res://addons/foveacore/scripts/reconstruction/splat_processor_helper.gd")
	_assert("SplatProcessorHelper loaded", helper_script != null)
	
	if helper_script:
		var green_splat = GaussianSplat.new()
		green_splat.color = Color(0.2, 0.6, 0.1) # Vert dominant
		
		var brown_splat = GaussianSplat.new()
		brown_splat.color = Color(0.5, 0.35, 0.1) # Marron
		
		var grey_splat = GaussianSplat.new()
		grey_splat.color = Color(0.3, 0.3, 0.3) # Gris écorce/pierre
		
		var red_splat = GaussianSplat.new()
		red_splat.color = Color(0.9, 0.1, 0.1) # Rouge standard
		
		var test_splats: Array[GaussianSplat] = [green_splat, brown_splat, grey_splat, red_splat]
		
		helper_script.auto_tag_splats_by_color(test_splats)
		_assert("Green splat tagged as LEAVES", green_splat.layer_type == GaussianSplat.LayerType.LEAVES)
		_assert("Brown splat tagged as TRUNK", brown_splat.layer_type == GaussianSplat.LayerType.TRUNK)
		_assert("Grey splat tagged as TRUNK", grey_splat.layer_type == GaussianSplat.LayerType.TRUNK)
		_assert("Red splat tagged as BASE", red_splat.layer_type == GaussianSplat.LayerType.BASE)
		
		var flat_splat = GaussianSplat.new()
		flat_splat.scale = Vector3(3.0, 0.5, 0.1) # Anisotropie élevée
		
		var round_splat = GaussianSplat.new()
		round_splat.scale = Vector3(1.0, 1.0, 0.9) # Quasi isotrope
		
		var shape_splats: Array[GaussianSplat] = [flat_splat, round_splat]
		helper_script.assign_shapes(shape_splats, "Auto")
		_assert("Flat splat assigned SPONGE (Triangle) shape in Auto mode", flat_splat.brush_type == GaussianSplat.BrushType.SPONGE)
		_assert("Round splat assigned GAUSSIAN (Sphere) shape in Auto mode", round_splat.brush_type == GaussianSplat.BrushType.GAUSSIAN)
		
		var dec_splats: Array[GaussianSplat] = []
		for i in range(100):
			dec_splats.append(GaussianSplat.new())
		var decimated = helper_script.decimate_splats(dec_splats, 0.3)
		_assert("Decimation reduces size to 30%", decimated.size() == 30)

	if _failed > 0:
		_finish()
		return

	# 2. Create a session with dry_run enabled
	var test_name = "dry_run_test_session"
	_session = _manager.create_new_session("", test_name)
	_session.output_directory = "user://test_dry_run_session_dir"
	_session.dry_run = true
	_session.use_worldmirror = false # Test the SfM + 3DGS pipeline path
	_session.use_artifixer = true # Test the ArtiFixer refinement path


	_assert("Session created successfully", _session != null)
	_assert("Session dry_run is true", _session.dry_run == true)

	# 3. Save the session (JSON format check)
	var err = _manager.save_session(_session)
	_assert("Session JSON save returns OK", err == OK)
	
	var json_path = _session.output_directory.path_join("session.json")
	var file_exists = FileAccess.file_exists(json_path)
	_assert("session.json was created on disk", file_exists)

	if file_exists:
		var loaded_session = _manager.load_session(json_path)
		_assert("Session loaded successfully from JSON", loaded_session != null)
		if loaded_session:
			_assert("Loaded session name matches", loaded_session.session_name == test_name)
			_assert("Loaded session dry_run is true", loaded_session.dry_run == true)

	# 4. Connect signals to track progress and completion
	var progress_values := []
	_manager.session_progress_updated.connect(func(progress: float):
		progress_values.append(progress)
		print("  [SIGNAL] Progress updated: %.2f%%" % progress)
	)

	_manager.session_completed.connect(func(sess: ReconstructionSession):
		_completed = true
		_assert("Completed session is the same instance", sess == _session)
		print("  [SIGNAL] Session completed successfully!")
	)

	_manager.reconstruction_failed.connect(func(reason: String):
		_completed = true
		_assert("Pipeline should not fail in dry run", false, reason)
		print("  [SIGNAL] Reconstruction failed: " + reason)
	)

	# 5. Run the reconstruction pipeline in Dry Run mode
	print("\nStarting dry run pipeline...")
	_manager.run_reconstruction(_session)

	# Wait for completion (dry run should complete in a few seconds)
	var timeout := 10.0
	var elapsed := 0.0
	while not _completed and elapsed < timeout:
		await create_timer(0.2).timeout
		elapsed += 0.2

	_assert("Pipeline completed within timeout", _completed)

	if _completed:
		# Check directories were created
		var global_dir = ProjectSettings.globalize_path(_session.output_directory)
		_assert("Workspace directory exists", DirAccess.dir_exists_absolute(global_dir))
		_assert("images directory exists", DirAccess.dir_exists_absolute(global_dir.path_join("images")))
		_assert("input directory exists", DirAccess.dir_exists_absolute(global_dir.path_join("input")))
		_assert("masks directory exists", DirAccess.dir_exists_absolute(global_dir.path_join("masks")))
		if not _session.dry_run:
			_assert("sparse directory exists", DirAccess.dir_exists_absolute(global_dir.path_join("sparse")))

		# Check progress progression
		_assert("Received progress updates", progress_values.size() > 0)
		if progress_values.size() > 0:
			var last_progress = progress_values[-1]
			_assert("Final progress is 100%", is_equal_approx(last_progress, 100.0) or last_progress >= 99.9)

		# Clean up output files created during test
		print("\nCleaning up test directory...")
		_manager.delete_session(_session, true)
		_assert("Workspace directory cleaned up", not DirAccess.dir_exists_absolute(global_dir))

	_finish()

func _finish() -> void:
	print("\n" + "=".repeat(70))
	print("StudioTo3D Pipeline Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	
	# Clean up manager node
	if _manager and is_instance_valid(_manager):
		_manager.queue_free()
		
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		if detail.is_empty():
			print("  ✗ %s" % name)
		else:
			print("  ✗ %s — %s" % [name, detail])
