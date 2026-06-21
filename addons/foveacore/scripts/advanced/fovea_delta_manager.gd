class_name FoveaDeltaManager
extends RefCounted

## FoveaEngine : Gestionnaire de variantes d'instances Delta-Splat (Task 245 & 246)
## Gère le stockage en VRAM sous forme de buffers condensés FP16 et l'interpolation temporelle.

# Dictionnaire des instances enregistrées :
# instance_id -> { "buffer_rid": RID, "weight": float, "target_weight": float, "splat_count": int }
var _instances := {}
var rd: RenderingDevice = null

func _init() -> void:
	# Récupérer le RenderingDevice principal de Godot
	rd = RenderingServer.get_rendering_device()

## Enregistre une nouvelle instance delta et génère son buffer VRAM compressé en FP16
func register_instance(instance_id: int, splat_count: int, delta_positions: Dictionary, delta_colors: Dictionary, delta_normals: Dictionary) -> RID:
	if not rd:
		push_error("FoveaDeltaManager: RenderingDevice indisponible.")
		return RID()
		
	# Nettoyer l'ancienne instance si elle existe déjà
	unregister_instance(instance_id)
	
	# Structure GPU (24 octets par splat) :
	# uint pos_xy (FP16 X, Y)
	# uint pos_z_pad (FP16 Z, 16 bits de padding)
	# uint col_rg (FP16 R, G)
	# uint col_ba (FP16 B, A)
	# uint norm_uv (FP16 U, V)
	# uint padding (32 bits)
	var byte_size := splat_count * 24
	var buffer_bytes := PackedByteArray()
	buffer_bytes.resize(byte_size)
	
	# Encoder en FP16 les entrées de deltas
	for i in range(splat_count):
		var offset := i * 24
		
		# Position
		var pos := delta_positions.get(i, Vector3.ZERO) as Vector3
		buffer_bytes.encode_u32(offset, FoveaDeltaData.pack_half_2x16(pos.x, pos.y))
		buffer_bytes.encode_u32(offset + 4, FoveaDeltaData.float_to_half(pos.z) & 0xFFFF)
		
		# Color
		var col := delta_colors.get(i, Color(0, 0, 0, 0)) as Color
		buffer_bytes.encode_u32(offset + 8, FoveaDeltaData.pack_half_2x16(col.r, col.g))
		buffer_bytes.encode_u32(offset + 12, FoveaDeltaData.pack_half_2x16(col.b, col.a))
		
		# Normal
		var norm := delta_normals.get(i, Vector2.ZERO) as Vector2
		buffer_bytes.encode_u32(offset + 16, FoveaDeltaData.pack_half_2x16(norm.x, norm.y))
		
		# Padding
		buffer_bytes.encode_u32(offset + 20, 0)
		
	var buffer_rid := rd.storage_buffer_create(byte_size, buffer_bytes)
	
	_instances[instance_id] = {
		"buffer_rid": buffer_rid,
		"weight": 0.0,
		"target_weight": 0.0,
		"splat_count": splat_count
	}
	
	return buffer_rid

## Supprime et libère les ressources GPU d'une instance delta
func unregister_instance(instance_id: int) -> void:
	if _instances.has(instance_id):
		var info: Dictionary = _instances[instance_id]
		var buffer_rid: RID = info.buffer_rid
		if rd and buffer_rid.is_valid():
			rd.free_rid(buffer_rid)
		_instances.erase(instance_id)

## Met à jour l'interpolation temporelle des poids d'application des deltas
func process_interpolation(delta_time: float, interpolation_speed: float = 5.0) -> void:
	for inst_id in _instances.keys():
		var info: Dictionary = _instances[inst_id]
		var current: float = info.weight
		var target: float = info.target_weight
		
		if not is_equal_approx(current, target):
			var new_weight := move_toward(current, target, interpolation_speed * delta_time)
			info.weight = clampf(new_weight, 0.0, 1.0)

## Définit le coefficient cible de transition (0.0 -> 1.0)
func set_instance_target_weight(instance_id: int, weight: float) -> void:
	if _instances.has(instance_id):
		_instances[instance_id].target_weight = clampf(weight, 0.0, 1.0)

## Récupère le poids d'application actuel (interpolé) d'un delta
func get_instance_weight(instance_id: int) -> float:
	if _instances.has(instance_id):
		return _instances[instance_id].weight
	return 0.0

## Récupère le RID du buffer GPU stockant les deltas compressés
func get_instance_buffer(instance_id: int) -> RID:
	if _instances.has(instance_id):
		return _instances[instance_id].buffer_rid
	return RID()

## Libération complète du gestionnaire
func cleanup() -> void:
	var keys := _instances.keys()
	for key in keys:
		unregister_instance(key)
	_instances.clear()

## Version statique pour compatibilité avec le culling d'instances (FoveaInstancedCuller)
static func pack_gpu_deltas(active_delta_positions: Array[Dictionary], active_delta_colors: Array[Dictionary]) -> Dictionary:
	var offsets_bytes := PackedByteArray()
	var deltas_bytes := PackedByteArray()
	
	offsets_bytes.resize((active_delta_positions.size() + 1) * 4)
	
	var current_offset := 0
	offsets_bytes.encode_u32(0, 0)
	
	for i in range(active_delta_positions.size()):
		var pos_dict := active_delta_positions[i]
		var col_dict := active_delta_colors[i]
		
		# Trouver les indices uniques avec deltas pour cette instance
		var indices := {}
		for k in pos_dict.keys():
			indices[k] = true
		for k in col_dict.keys():
			indices[k] = true
			
		var sorted_keys := indices.keys()
		sorted_keys.sort()
		
		for idx: int in sorted_keys:
			var pos: Vector3 = pos_dict.get(idx, Vector3.ZERO)
			var col: Color = col_dict.get(idx, Color(1, 1, 1, 1)) # Delta multiplicateur
			
			var entry_offset := deltas_bytes.size()
			deltas_bytes.resize(entry_offset + 16)
			
			# local_idx (uint32)
			deltas_bytes.encode_u32(entry_offset, idx)
			# pos_xy (FP16 packed)
			deltas_bytes.encode_u32(entry_offset + 4, FoveaDeltaData.pack_half_2x16(pos.x, pos.y))
			# pos_z (FP16 Z in lower 16, upper 16 pad)
			deltas_bytes.encode_u32(entry_offset + 8, FoveaDeltaData.float_to_half(pos.z) & 0xFFFF)
			# color (RGBA packed: R (MSB) to A (LSB))
			var r_byte := clampi(int(col.r * 255.0), 0, 255)
			var g_byte := clampi(int(col.g * 255.0), 0, 255)
			var b_byte := clampi(int(col.b * 255.0), 0, 255)
			var a_byte := clampi(int(col.a * 255.0), 0, 255)
			var color_packed := (r_byte << 24) | (g_byte << 16) | (b_byte << 8) | a_byte
			deltas_bytes.encode_u32(entry_offset + 12, color_packed)
			
			current_offset += 1
			
		offsets_bytes.encode_u32((i + 1) * 4, current_offset)
		
	return {
		"offsets_bytes": offsets_bytes,
		"deltas_bytes": deltas_bytes
	}
