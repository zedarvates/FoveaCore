extends Node

const FoveaMultiplayerSyncScript = preload("res://addons/foveacore/scripts/vr/fovea_multiplayer_sync.gd")
const SplatBrushEngineScript = preload("res://addons/foveacore/scripts/advanced/splat_brush_engine.gd")
const FoveaVRRigScript = preload("res://addons/foveacore/scripts/vr/fovea_vr_rig.gd")
const FoveaSplattableScript = preload("res://addons/foveacore/scripts/fovea_splattable.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")


func _ready() -> void:
	print("\n==============================================")
	print("=== Fovea Engine - Multiplayer VR Sync Test ===")
	print("==============================================\n")
	
	var success = true
	success = success and test_multiplayer_sync_instantiation()
	success = success and test_pose_sync()
	success = success and test_brush_sync()
	
	if success:
		print("=== MULTIPLAYER SYNC TESTS PASSED ===")
	else:
		push_error("=== MULTIPLAYER SYNC TESTS FAILED ===")
		
	if OS.has_feature("headless") or "--quit" in OS.get_cmdline_args():
		get_tree().quit(0 if success else 1)


func test_multiplayer_sync_instantiation() -> bool:
	print("Testing instantiation...")
	var sync_node = FoveaMultiplayerSyncScript.new()
	if sync_node == null:
		push_error("Failed to instantiate FoveaMultiplayerSync")
		return false
	add_child(sync_node)
	sync_node.queue_free()
	print("Instantiation test passed.")
	return true


func test_pose_sync() -> bool:
	print("Testing pose synchronization...")
	# Set up a dummy local rig
	var rig = FoveaVRRigScript.new()
	add_child(rig)
	
	# Force component creation in rig
	var cam = XRCamera3D.new()
	cam.name = "XRCamera3D"
	rig.add_child(cam)
	
	var lh = XRController3D.new()
	lh.name = "LeftHand"
	rig.add_child(lh)
	
	var rh = XRController3D.new()
	rh.name = "RightHand"
	rig.add_child(rh)
	
	# Instantiate MultiplayerSync
	var sync_node = FoveaMultiplayerSyncScript.new()
	sync_node.local_rig = rig
	add_child(sync_node)
	
	# Call update_peer_pose directly to test interpolation setup
	var head_pos = Vector3(1, 2, 3)
	var head_rot = Quaternion.IDENTITY
	var head_vel = Vector3.ZERO
	
	var left_pos = Vector3(-0.2, 1.0, -0.5)
	var left_rot = Quaternion.IDENTITY
	var left_vel = Vector3.ZERO
	
	var right_pos = Vector3(0.2, 1.0, -0.5)
	var right_rot = Quaternion.IDENTITY
	var right_vel = Vector3.ZERO
	
	var timestamp = Time.get_unix_time_from_system()
	
	# Simulate receiving pose update from peer 2
	sync_node.update_peer_pose(
		head_pos, head_rot, head_vel,
		left_pos, left_rot, left_vel,
		right_pos, right_rot, right_vel,
		timestamp
	)
	
	# Check if rig was spawned
	if not sync_node._remote_rigs.has(2):
		push_error("Failed to spawn remote rig for peer 2")
		rig.queue_free()
		sync_node.queue_free()
		return false
		
	var rig_data = sync_node._remote_rigs[2]
	if not is_instance_valid(rig_data.root):
		push_error("Spawned remote rig root is invalid")
		rig.queue_free()
		sync_node.queue_free()
		return false
		
	# Feed a second snapshot slightly later to allow interpolation
	var dt = 0.1
	sync_node.update_peer_pose(
		head_pos + Vector3(0.1, 0, 0), head_rot, Vector3(1.0, 0, 0),
		left_pos, left_rot, left_vel,
		right_pos, right_rot, right_vel,
		timestamp + dt
	)
	
	# Run process to interpolate
	var mock_time = timestamp + dt
	var state = sync_node._head_interpolator.get_interpolated_state(2, mock_time)
	if state == null:
		push_error("Failed to get interpolated state")
		rig.queue_free()
		sync_node.queue_free()
		return false
		
	print("Interpolated head position: ", state.position)
	if not state.position.is_equal_approx(head_pos):
		push_error("Interpolated head position mismatch. Expected: %s, Got: %s" % [str(head_pos), str(state.position)])
		rig.queue_free()
		sync_node.queue_free()
		return false
		
	rig.queue_free()
	sync_node.queue_free()
	print("Pose synchronization test passed.")
	return true


func test_brush_sync() -> bool:
	print("Testing brush synchronization...")
	# Create dummy splattable
	var splattable = FoveaSplattableScript.new()
	splattable.name = "TestSplattable"
	add_child(splattable)
	
	# Create a dummy splat
	var splat = GaussianSplatScript.new(Vector3.ZERO)
	splat.color = Color.BLACK
	splat.opacity = 1.0
	splattable.loaded_splats.append(splat)
	
	# Instantiate MultiplayerSync
	var sync_node = FoveaMultiplayerSyncScript.new()
	add_child(sync_node)
	
	# Simulate receiving replicated brush stroke (PAINT)
	sync_node.replicate_brush_stroke(
		splattable.get_path(),
		Vector3.ZERO,
		0, # PAINT
		1.0, # radius
		Color.GREEN,
		1.0, # opacity
		Vector3.UP # flow_dir
	)
	
	# Verify that splat was painted Green
	var modified_splat = splattable.loaded_splats[0]
	print("Splat color after brush replication: ", modified_splat.color)
	if modified_splat.color != Color.GREEN:
		push_error("Brush replication did not paint the splat green.")
		splattable.queue_free()
		sync_node.queue_free()
		return false
		
	splattable.queue_free()
	sync_node.queue_free()
	print("Brush synchronization test passed.")
	return true
