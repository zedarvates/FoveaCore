class_name FoveaDeltaManagerPlugin
extends FoveaDeltaManager

## FoveaEngine — Delta Variants (items 206-217)
## Instance-level overrides: color tint, position offset, scale delta.

func set_instance_delta(instance_id: int, delta: Dictionary) -> void:
	var packed = PackedFloat32Array()
	packed.resize(16)  # 4 × vec4 for position/color/scale/normal deltas
	packed[0] = delta.get("dx", 0.0)
	packed[1] = delta.get("dy", 0.0)
	packed[2] = delta.get("dz", 0.0)
	packed[4] = delta.get("dr", 0.0)
	packed[5] = delta.get("dg", 0.0)
	packed[6] = delta.get("db", 0.0)
	packed[8] = delta.get("sx", 1.0)
	packed[9] = delta.get("sy", 1.0)
	packed[10] = delta.get("sz", 1.0)
	_store_instance_override(instance_id, packed)
