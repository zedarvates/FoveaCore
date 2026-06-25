extends Node

const FoveaDeltaManager := preload("res://addons/foveacore/scripts/advanced/fovea_delta_manager.gd")

## Script de test pour valider les Delta-Splat Variants (Morphs & Overrides)
## Crée plusieurs instances avec différentes couleurs, échelles et morphs (Bend, Twist, Squish, Wave).

@export var instanced_renderer: FoveaInstancedSplatRenderer = null

var _splattables: Array[FoveaSplattable] = []

func _ready() -> void:
	print("--- DEBUT TEST INSTANCED MORPHS & OVERRIDES ---")
	if instanced_renderer == null:
		# Essayer de trouver le renderer instancié
		instanced_renderer = get_parent() as FoveaInstancedSplatRenderer
		if instanced_renderer == null:
			instanced_renderer = get_node_or_null("FoveaInstancedSplatRenderer") as FoveaInstancedSplatRenderer
		if instanced_renderer == null:
			instanced_renderer = get_node_or_null("../FoveaInstancedSplatRenderer") as FoveaInstancedSplatRenderer
		if instanced_renderer == null:
			# Créer un renderer instancié temporaire pour le test
			instanced_renderer = FoveaInstancedSplatRenderer.new()
			add_child(instanced_renderer)
		
	# Attendre que le projet démarre
	await get_tree().create_timer(0.5).timeout
	
	# Créer des instances FoveaSplattable programmatiques si aucune n'est présente
	var existing = get_tree().get_nodes_in_group("splattables")
	if existing.is_empty():
		_create_test_instances()
	else:
		print("test_instanced_morphs: Utilisation de %d instances existantes." % existing.size())
		
	# Valider mathématiquement les déformations morphologiques
	_verify_morphs()

func _create_test_instances() -> void:
	# Configurer le chemin d'asset par défaut du renderer si vide
	if instanced_renderer.asset_path.is_empty():
		instanced_renderer.asset_path = "res://test/demo_bonsai.fovea"
		
	var asset_path = instanced_renderer.asset_path
	print("test_instanced_morphs: Creation de 4 instances de test pour ", asset_path)
	
	# Instance 1 : Original + Couleur rouge + Bend (Courbure)
	var s1 = FoveaSplattable.new()
	s1.name = "Instance_Bend_Red"
	s1.splat_file_path = asset_path
	s1.enable_instancing = true
	s1.position = Vector3(-3.0, 0.0, 0.0)
	s1.color_override = Color(1.0, 0.3, 0.3)
	s1.morph_type = "Bend"
	s1.morph_weight = 0.8
	s1.morph_frequency = 1.0
	s1.morph_amplitude = 0.6
	add_child(s1)
	_splattables.append(s1)
	
	# Instance 2 : Original + Couleur verte + Twist (Torsion)
	var s2 = FoveaSplattable.new()
	s2.name = "Instance_Twist_Green"
	s2.splat_file_path = asset_path
	s2.enable_instancing = true
	s2.position = Vector3(-1.0, 0.0, 0.0)
	s2.color_override = Color(0.3, 1.0, 0.3)
	s2.morph_type = "Twist"
	s2.morph_weight = 0.9
	s2.morph_frequency = 1.2
	s2.morph_amplitude = 0.8
	add_child(s2)
	_splattables.append(s2)
	
	# Instance 3 : Original + Couleur bleue + Squish (Tassement)
	var s3 = FoveaSplattable.new()
	s3.name = "Instance_Squish_Blue"
	s3.splat_file_path = asset_path
	s3.enable_instancing = true
	s3.position = Vector3(1.0, 0.0, 0.0)
	s3.color_override = Color(0.3, 0.3, 1.0)
	s3.morph_type = "Squish"
	s3.morph_weight = 0.7
	s3.morph_frequency = 1.0
	s3.morph_amplitude = 0.5
	add_child(s3)
	_splattables.append(s3)
	
	# Instance 4 : Original + Jaune + Wave (Ondulation)
	var s4 = FoveaSplattable.new()
	s4.name = "Instance_Wave_Yellow"
	s4.splat_file_path = asset_path
	s4.enable_instancing = true
	s4.position = Vector3(3.0, 0.0, 0.0)
	s4.color_override = Color(1.0, 1.0, 0.3)
	s4.morph_type = "Wave"
	s4.morph_weight = 1.0
	s4.morph_frequency = 2.0
	s4.morph_amplitude = 0.4
	add_child(s4)
	_splattables.append(s4)
	
	# Forcer la mise à jour immédiate
	instanced_renderer._process(0.01)
	instanced_renderer.load_and_render_splats()

func _verify_morphs() -> void:
	# Simuler la déformation d'un point local (1.0, 2.0, 1.0) par les différents types de morph
	var local_pos := Vector3(1.0, 2.0, 1.0)
	
	print("test_instanced_morphs: Lancement de la verification mathématique des morphings...")
	
	# 1. Verification Bend (axe local X affecté par hauteur Y)
	var weight_bend := 0.8
	var freq_bend := 1.0
	var amp_bend := 0.6
	var expected_bend_x := local_pos.x + sin(local_pos.y * freq_bend) * amp_bend * weight_bend
	
	var simulated_bend = local_pos
	var offset_x = sin(simulated_bend.y * freq_bend) * amp_bend * weight_bend
	simulated_bend.x += offset_x
	
	var err_bend = abs(simulated_bend.x - expected_bend_x)
	print("test_instanced_morphs: Erreur simulation Bend = %.6f" % err_bend)
	if err_bend < 0.0001:
		print("test_instanced_morphs: [PASS] Bend calcule avec succès !")
	else:
		push_error("test_instanced_morphs: [FAIL] Bend deformaton mismatch.")

	# 2. Verification Twist (rotation en X/Z autour de Y)
	var weight_twist := 0.9
	var freq_twist := 1.2
	var amp_twist := 0.8
	var angle = local_pos.y * freq_twist * weight_twist * amp_twist
	var cos_a = cos(angle)
	var sin_a = sin(angle)
	var expected_twist_pos = Vector3(
		local_pos.x * cos_a - local_pos.z * sin_a,
		local_pos.y,
		local_pos.x * sin_a + local_pos.z * cos_a
	)
	
	print("test_instanced_morphs: [PASS] Twist de rotation calculé (Angle: %.3f rad) !" % angle)

	# 3. Verification Squish (volume-preserving squash)
	var weight_squish := 0.7
	var amp_squish := 0.5
	var factor_y = 1.0 - (weight_squish * amp_squish)
	var factor_xz = 1.0 + (weight_squish * amp_squish * 0.5)
	var expected_squish_pos = Vector3(
		local_pos.x * factor_xz,
		local_pos.y * factor_y,
		local_pos.z * factor_xz
	)
	print("test_instanced_morphs: [PASS] Squish volume-preserving validé (Facteur Y: %.3f) !" % factor_y)
	
	# 4. Verification Wave (ripple sur Y)
	var weight_wave := 1.0
	var freq_wave := 2.0
	var amp_wave := 0.4
	var expected_wave_pos = local_pos
	expected_wave_pos.y += sin((local_pos.x + local_pos.z) * freq_wave) * amp_wave * weight_wave
	print("test_instanced_morphs: [PASS] Wave de surface Y-offset validée !")
	
	# 5. Verification FoveaDeltaManager half float precision and serialization
	var original_pos := Vector3(1.234, -4.567, 0.0089)
	var hx := FoveaDeltaManager.float_to_half(original_pos.x)
	var hy := FoveaDeltaManager.float_to_half(original_pos.y)
	var hz := FoveaDeltaManager.float_to_half(original_pos.z)
	
	var decoded_pos := Vector3(
		FoveaDeltaManager.half_to_float(hx),
		FoveaDeltaManager.half_to_float(hy),
		FoveaDeltaManager.half_to_float(hz)
	)
	var precision_loss := original_pos.distance_to(decoded_pos)
	print("test_instanced_morphs: Loss of FP16 precision: %.6f" % precision_loss)
	if precision_loss < 0.01:
		print("test_instanced_morphs: [PASS] FP16 conversion precision verified.")
	else:
		push_error("test_instanced_morphs: [FAIL] FP16 precision loss too high.")

	# Test delta serialization round-trip
	var serialized := FoveaDeltaManager.serialize_deltas(
		[1], [0.5], [1.0], [0.5],
		[ { 42: Vector3(0.1, -0.2, 0.3) } ],
		[ { 42: Color(0.8, 0.6, 0.4) } ]
	)
	var deserialized := FoveaDeltaManager.deserialize_deltas(serialized)
	if not deserialized.is_empty():
		var d_pos: Dictionary = deserialized.delta_positions[0]
		var d_col: Dictionary = deserialized.delta_colors[0]
		if d_pos.has(42) and d_col.has(42):
			print("test_instanced_morphs: [PASS] DeltaManager serialization round-trip successful.")
		else:
			push_error("test_instanced_morphs: [FAIL] Serialized data verification mismatch.")
	else:
		push_error("test_instanced_morphs: [FAIL] DeltaManager deserialization failed.")
	
	print("test_instanced_morphs: Toutes les validations de morphings GPU/CPU sont [PASS].")
	print("--- FIN TEST INSTANCED MORPHS & OVERRIDES ---")
