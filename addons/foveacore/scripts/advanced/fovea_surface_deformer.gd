class_name FoveaSurfaceDeformer
extends Node3D

## FoveaEngine — Surface Deformer
## Déformation CPU/Compute répétable et bouclable pour les surfaces Gaussian Splats.
## Idéal pour simuler de l'eau, du tissu, ou des surfaces ondulantes périodiques.

enum DeformationType {
	GERSTNER_WAVES,
	NOISE_FIELD
}

@export var enabled: bool = true
@export var type: DeformationType = DeformationType.GERSTNER_WAVES

@export_group("Wave Parameters")
@export var wave_speed: float = 1.0
@export var wave_amplitude: float = 0.2
@export var wave_frequency: float = 0.5
@export var wave_tiling_size: float = 10.0
@export var wave_loop_period: float = 4.0

## Limiter le nombre de splats traités par frame pour les performances CPU
## 0 = pas de limite (tout traiter à chaque frame)
@export var max_splats_per_frame: int = 50000

## Référence au renderer parent
var _renderer: FoveaCoreSplatRenderer = null
var _time: float = 0.0
var _original_transforms_cache: Array[Transform3D] = []
var _last_instance_id: int = 0

func _ready() -> void:
	var parent := get_parent()
	if parent is FoveaCoreSplatRenderer:
		_renderer = parent
		print("FoveaSurfaceDeformer: Connecté à FoveaCoreSplatRenderer '%s'" % parent.name)

func _process(delta: float) -> void:
	if not enabled or _renderer == null or _renderer.multimesh == null:
		return
		
	var mm: MultiMesh = _renderer.multimesh
	if mm.instance_count == 0:
		return
		
	_time += delta
	
	# Vérifier si les transforms d'origine ont été mis à jour dans le renderer
	var current_id = mm.get_instance_id()
	if _original_transforms_cache.is_empty() or current_id != _last_instance_id or _original_transforms_cache.size() != mm.instance_count:
		_sync_transforms(mm)
		
	if _original_transforms_cache.is_empty():
		return
		
	_apply_deformation(mm)

func _sync_transforms(mm: MultiMesh) -> void:
	_last_instance_id = mm.get_instance_id()
	# Si le renderer a déjà un cache de transforms originaux, on l'utilise
	if _renderer and not _renderer._original_transforms.is_empty():
		_original_transforms_cache = _renderer._original_transforms.duplicate()
	else:
		# Sinon on fait un snapshot nous-mêmes
		_original_transforms_cache.clear()
		_original_transforms_cache.resize(mm.instance_count)
		for i in mm.instance_count:
			_original_transforms_cache[i] = mm.get_instance_transform(i)
	print("FoveaSurfaceDeformer: Cache de %d transforms originaux synchronisé." % _original_transforms_cache.size())

func _apply_deformation(mm: MultiMesh) -> void:
	var count := mm.instance_count
	var limit := count if max_splats_per_frame <= 0 else mini(count, max_splats_per_frame)
	var looped_time := fmod(_time, wave_loop_period)
	var time_ratio := (looped_time * wave_speed * (2.0 * PI / wave_loop_period))

	# Écriture bulk (règle Batch Processing) : une seule affectation GPU par frame
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf: PackedFloat32Array = mm.buffer

	for i in limit:
		if i >= _original_transforms_cache.size():
			break
			
		var original_xf := _original_transforms_cache[i]
		var world_pos := original_xf.origin
		
		# Application du pavage spatial (tiling)
		var tiled_x := fmod(world_pos.x, wave_tiling_size)
		if tiled_x < 0.0: tiled_x += wave_tiling_size
		var tiled_z := fmod(world_pos.z, wave_tiling_size)
		if tiled_z < 0.0: tiled_z += wave_tiling_size
		
		var displacement_y: float = 0.0
		var slope_x: float = 0.0
		var slope_z: float = 0.0
		
		match type:
			DeformationType.GERSTNER_WAVES:
				# Vague de Gerstner simple en coordonnées bouclables
				var wave_angle := (tiled_x + tiled_z) * wave_frequency + time_ratio
				displacement_y = sin(wave_angle) * wave_amplitude
				
				# Dérivées analytiques de sin((x+z)*freq + time) * amp
				var cos_angle := cos(wave_angle)
				slope_x = cos_angle * wave_amplitude * wave_frequency
				slope_z = cos_angle * wave_amplitude * wave_frequency
				
			DeformationType.NOISE_FIELD:
				# Un bruit pseudo-aléatoire basé sur des sinus superposés pour être parfaitement périodique
				# dans l'espace (tiling) et le temps (looping)
				var spatial_angle_x := tiled_x * (2.0 * PI / wave_tiling_size)
				var spatial_angle_z := tiled_z * (2.0 * PI / wave_tiling_size)
				
				var n1 := sin(spatial_angle_x + time_ratio) * cos(spatial_angle_z + time_ratio)
				var n2 := sin(spatial_angle_x * 2.0 - time_ratio) * sin(spatial_angle_z * 2.0 + time_ratio * 0.5) * 0.5
				displacement_y = (n1 + n2) * wave_amplitude
				
				# Dérivées analytiques
				var k: float = 2.0 * PI / wave_tiling_size
				
				var dn1_dx := k * cos(spatial_angle_x + time_ratio) * cos(spatial_angle_z + time_ratio)
				var dn1_dz := -k * sin(spatial_angle_x + time_ratio) * sin(spatial_angle_z + time_ratio)
				
				var dn2_dx := k * cos(spatial_angle_x * 2.0 - time_ratio) * sin(spatial_angle_z * 2.0 + time_ratio * 0.5)
				var dn2_dz := k * sin(spatial_angle_x * 2.0 - time_ratio) * cos(spatial_angle_z * 2.0 + time_ratio * 0.5)
				
				slope_x = (dn1_dx + dn2_dx) * wave_amplitude
				slope_z = (dn1_dz + dn2_dz) * wave_amplitude
				
		var n_vec := Vector3(-slope_x, 1.0, -slope_z).normalized()
		var t_vec := Vector3.RIGHT.slide(n_vec).normalized()
		var b_vec := n_vec.cross(t_vec).normalized()
		var wave_basis := Basis(t_vec, b_vec, n_vec)
		
		var final_xf := original_xf
		final_xf.origin.y += displacement_y
		final_xf.basis = wave_basis * original_xf.basis
		
		FoveaMultiMeshBulk.write_transform(buf, i * stride, final_xf)

	mm.buffer = buf
