class_name FoveaCloudAnimator
extends Node3D

## FoveaEngine — Cloud Animator
## Controls the creation, drifting, and dissipation cycle of cloud Gaussian Splats.

@export var enabled: bool = true
@export var cycle_duration: float = 10.0
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
@export var wind_speed: float = 0.5
@export var turbulence_strength: float = 0.2
@export var dissipation_spread: float = 2.0
@export var max_splats_per_frame: int = 50000

var _renderer: FoveaCoreSplatRenderer = null
var _time: float = 0.0
var _original_transforms_cache: Array[Transform3D] = []
var _original_custom_data_cache: Array[Color] = []
var _last_instance_id: int = 0
var _noise: FastNoiseLite = FastNoiseLite.new()

func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.05
	var parent := get_parent()
	if parent is FoveaCoreSplatRenderer:
		_renderer = parent
		print("FoveaCloudAnimator: Connected to FoveaCoreSplatRenderer '%s'" % parent.name)

func _process(delta: float) -> void:
	if not enabled or _renderer == null or _renderer.multimesh == null:
		return
	var mm: MultiMesh = _renderer.multimesh
	if mm.instance_count == 0:
		return
	
	_time += delta
	var current_id := mm.get_instance_id()
	if _original_transforms_cache.is_empty() or current_id != _last_instance_id or _original_transforms_cache.size() != mm.instance_count:
		_sync_transforms(mm)
	
	if _original_transforms_cache.is_empty():
		return
		
	_apply_cloud_animation(mm)

func _sync_transforms(mm: MultiMesh) -> void:
	_last_instance_id = mm.get_instance_id()
	_original_transforms_cache.clear()
	_original_transforms_cache.resize(mm.instance_count)
	_original_custom_data_cache.clear()
	_original_custom_data_cache.resize(mm.instance_count)
	
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf := mm.buffer
	var use_colors := mm.use_colors
	var use_custom := mm.use_custom_data
	
	for i in mm.instance_count:
		_original_transforms_cache[i] = mm.get_instance_transform(i)
		if use_custom:
			_original_custom_data_cache[i] = mm.get_instance_custom_data(i)
		else:
			_original_custom_data_cache[i] = Color(1, 1, 1, 1)
	
	print("FoveaCloudAnimator: Synced original cache for %d splats." % mm.instance_count)

func _apply_cloud_animation(mm: MultiMesh) -> void:
	var count := mm.instance_count
	var limit := count if max_splats_per_frame <= 0 else mini(count, max_splats_per_frame)
	
	var phase := fmod(_time, cycle_duration) / cycle_duration
	
	# Compute global animation curves based on phase (0.0 to 1.0)
	# 0.0 to 0.2: Fade-in and scale up (Creation)
	# 0.2 to 0.8: Fully visible, drifting (Drift)
	# 0.8 to 1.0: Fade-out and disperse (Dissipation)
	var global_alpha := 1.0
	var scale_factor := 1.0
	var dissipation_offset := 0.0
	
	if phase < 0.2:
		var t := phase / 0.2
		global_alpha = t
		scale_factor = t
	elif phase < 0.8:
		global_alpha = 1.0
		scale_factor = 1.0
	else:
		var t := (phase - 0.8) / 0.2
		global_alpha = 1.0 - t
		scale_factor = 1.0 - t * 0.3
		dissipation_offset = t * dissipation_spread
	
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf := mm.buffer
	var use_colors := mm.use_colors
	var use_custom := mm.use_custom_data
	
	var wind_disp := wind_direction.normalized() * wind_speed * _time
	
	for i in limit:
		if i >= _original_transforms_cache.size():
			break
			
		var orig_xf := _original_transforms_cache[i]
		var base_pos := orig_xf.origin
		
		# Compute turbulence noise offset
		var noise_val_x := _noise.get_noise_3dv(base_pos + Vector3(0, _time * 0.1, 0))
		var noise_val_y := _noise.get_noise_3dv(base_pos + Vector3(100, _time * 0.1, 0))
		var noise_val_z := _noise.get_noise_3dv(base_pos + Vector3(200, _time * 0.1, 0))
		var turbulence := Vector3(noise_val_x, noise_val_y, noise_val_z) * turbulence_strength
		
		# Dissipation offset moves splats away from the center of the cloud (diffusion)
		var center_disp := base_pos.normalized() * dissipation_offset
		
		var final_xf := orig_xf
		final_xf.origin += wind_disp + turbulence + center_disp
		final_xf.basis = final_xf.basis.scaled(Vector3(scale_factor, scale_factor, scale_factor))
		
		FoveaMultiMeshBulk.write_transform(buf, i * stride, final_xf)
		
		if use_custom:
			var orig_custom := _original_custom_data_cache[i]
			var final_custom := orig_custom
			final_custom.a *= global_alpha  # Modulate opacity
			
			var custom_offset := 12
			if use_colors:
				custom_offset += 4
			FoveaMultiMeshBulk.write_color(buf, i * stride + custom_offset, final_custom)
			
	mm.buffer = buf
