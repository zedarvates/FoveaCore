extends SceneTree

## Unit tests for FoveaAsset format serialization and deserialization
## Preloads all classes using script suffixes to avoid global class DB collisions.

const FoveaAssetScript := preload("res://addons/foveacore/scripts/fovea_asset.gd")
const FoveaAssetWriterScript := preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")
const FoveaAssetFormatLoaderScript := preload("res://addons/foveacore/scripts/fovea_asset_loader.gd")
const FoveaAssetFormatSaverScript := preload("res://addons/foveacore/scripts/fovea_asset_saver.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const FoveaStyleScript := preload("res://addons/foveacore/scripts/fovea_style.gd")
const FoveaMaterialScript := preload("res://addons/foveacore/scripts/fovea_material.gd")

var _passed := 0
var _failed := 0

signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaAsset Serialization/Deserialization Unit Tests")
	print("=".repeat(70))

	await create_timer(0.3).timeout
	_run_all()

func _run_all() -> void:
	_test_serialization_and_deserialization()
	
	print("\n" + "=".repeat(70))
	print("FoveaAsset Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_serialization_and_deserialization() -> void:
	print("\n--- _test_serialization_and_deserialization ---")
	
	# 1. Création de splats de test
	var splats: Array[RefCounted] = []
	for i in range(10):
		var s := GaussianSplatScript.new(Vector3(float(i), float(i) * 0.5, -float(i)))
		s.scale = Vector3(1.0 + i * 0.1, 1.2 - i * 0.05, 0.5)
		s.rotation = Quaternion.from_euler(Vector3(0.1 * i, 0.2 * i, 0.3 * i))
		s.color = Color(0.1 * i, 1.0 - 0.1 * i, 0.5, 1.0)
		s.opacity = 0.9 - i * 0.05
		s.normal = Vector3(0.0, 1.0, 0.0).rotated(Vector3(1.0, 0.0, 0.0), 0.1 * i).normalized()
		s.layer_type = 0 if i % 2 == 0 else 1 # BASE vs SATURATION
		s.dither_seed = i * 20
		splats.append(s)
		
	# 2. Création d'un style de test
	var style := FoveaStyleScript.new()
	style.mode = "procedural"
	style.detail = 1.5
	style.grain = 0.2
	style.light_coherence = 0.9
	style.color_saturation = 0.8
	style.micro_shadow = 0.4
	style.lora_path = "res://lora.safetensors"
	style.neural_strength = 0.1
	style.temporal_coherence = false
	
	var stone := FoveaMaterialScript.new()
	stone.material_type = 0 # STONE
	stone.base_color = Color(0.3, 0.4, 0.5)
	stone.roughness = 0.7
	stone.metallic = 0.1
	stone.bump_strength = 0.6
	stone.specular_strength = 0.2
	stone.noise_scale = 8.5
	stone.noise_octaves = 5
	stone.noise_lacunarity = 2.1
	stone.noise_gain = 0.45
	style.stone_params = stone
	
	# 3. Création d'un maillage de test simple
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)
	])
	var indices := PackedInt32Array([
		0, 1, 2, 1, 3, 2
	])
	var normals := PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# 4. Métadonnées personnalisées
	var metadata := {
		"creator": "FoveaEngine Test Suite",
		"timestamp": 1234567890,
		"tags": ["unit-test", "binary-format"],
		"version": "1.0"
	}
	
	# 5. Sérialisation
	var test_path := "user://test_asset.fovea"
	# Convertir le type statique pour l'injecter
	var typed_splats: Array[GaussianSplat] = []
	for s in splats:
		typed_splats.append(s as GaussianSplat)
		
	var success: bool = FoveaAssetWriterScript.write_fovea_asset(test_path, typed_splats, mesh, style, metadata)
	_assert("Serialize asset success", success, "write_fovea_asset a renvoyé true")
	
	# 6. Désérialisation via le loader
	var loader_instance := FoveaAssetFormatLoaderScript.new()
	var load_result: Variant = loader_instance._load(test_path, test_path, false, 0)
	
	_assert("Load asset not null", load_result is Resource, "Load a bien retourné une instance de ressource")
	if not load_result is Resource:
		return
		
	var loaded_asset := load_result # as FoveaAsset
	
	# 7. Validations des valeurs décodées
	_assert("Splat count matches", loaded_asset.splat_count == splats.size(), "%d == %d" % [loaded_asset.splat_count, splats.size()])
	var aabb_size: Vector3 = Vector3(loaded_asset.aabb_max) - Vector3(loaded_asset.aabb_min)
	_assert("AABB size greater than 0", aabb_size.length_squared() > 0.001, "AABB size: %s" % str(aabb_size))
	
	# Métadonnées
	_assert("Metadata creator matches", loaded_asset.metadata.get("creator") == "FoveaEngine Test Suite", str(loaded_asset.metadata.get("creator")))
	_assert("Metadata version matches", loaded_asset.metadata.get("version") == "1.0", str(loaded_asset.metadata.get("version")))
	_assert("Metadata tags count", loaded_asset.metadata.get("tags").size() == 2, "")
	
	# Style
	_assert("Style not null", loaded_asset.style != null, "")
	if loaded_asset.style != null:
		_assert("Style mode", loaded_asset.style.mode == "procedural", "")
		_assert("Style detail", is_equal_approx(loaded_asset.style.detail, 1.5), "")
		_assert("Style grain", is_equal_approx(loaded_asset.style.grain, 0.2), "")
		_assert("Style temporal_coherence", loaded_asset.style.temporal_coherence == false, "")
		_assert("Style stone_params not null", loaded_asset.style.stone_params != null, "")
		if loaded_asset.style.stone_params != null:
			_assert("Stone material_type", loaded_asset.style.stone_params.material_type == 0, "") # STONE
			_assert("Stone roughness", is_equal_approx(loaded_asset.style.stone_params.roughness, 0.7), "")
			_assert("Stone base_color", loaded_asset.style.stone_params.base_color.is_equal_approx(Color(0.3, 0.4, 0.5)), "")
			
	# Maillage
	_assert("Mesh not null", loaded_asset.mesh != null, "")
	if loaded_asset.mesh != null:
		_assert("Mesh surface count == 1", loaded_asset.mesh.get_surface_count() == 1, "")
		var loaded_arrays: Array = loaded_asset.mesh.surface_get_arrays(0)
		var loaded_vertices: PackedVector3Array = loaded_arrays[Mesh.ARRAY_VERTEX]
		var loaded_indices: PackedInt32Array = loaded_arrays[Mesh.ARRAY_INDEX]
		var loaded_normals: PackedVector3Array = loaded_arrays[Mesh.ARRAY_NORMAL]
		var loaded_uvs: PackedVector2Array = loaded_arrays[Mesh.ARRAY_TEX_UV]
		
		_assert("Mesh vertices count", loaded_vertices.size() == 4, "")
		_assert("Mesh indices count", loaded_indices.size() == 6, "")
		_assert("Mesh first vertex", loaded_vertices[0].is_equal_approx(Vector3(0, 0, 0)), "")
		_assert("Mesh last vertex", loaded_vertices[3].is_equal_approx(Vector3(1, 1, 0)), "")
		_assert("Mesh normals present", loaded_normals.size() == 4, "")
		_assert("Mesh UVs present", loaded_uvs.size() == 4, "")

	# Données GPU
	_assert("Palette not null", loaded_asset.color_palette != null, "")
	if loaded_asset.color_palette != null:
		_assert("Palette colors not empty", not loaded_asset.color_palette.colors.is_empty(), "Taille: %d couleurs" % loaded_asset.color_palette.colors.size())
	_assert("Covariance bytes not empty", not loaded_asset.covariance_codebook.is_empty(), "Taille: %d octets" % loaded_asset.covariance_codebook.size())
	_assert("Raw splats bytes count", loaded_asset.splats_raw_bytes.size() == splats.size() * 16, "Taille: %d octets" % loaded_asset.splats_raw_bytes.size())

	# 8. Test de sauvegarde/re-chargement via le format_saver et format_loader de Godot
	var saver_instance := FoveaAssetFormatSaverScript.new()
	var test_save_path := "user://test_saver_output.fovea"
	var err: Error = saver_instance._save(loaded_asset, test_save_path, 0)
	_assert("Save loaded asset via saver success", err == OK, "Error code: %d" % err)
	
	var reload_result: Variant = loader_instance._load(test_save_path, test_save_path, false, 0)
	_assert("Reload saved asset not null", reload_result is Resource, "Reload via loader succeeded")
	if reload_result is Resource:
		_assert("Reload splat count", reload_result.splat_count == loaded_asset.splat_count, "")
		_assert("Reload metadata matches", reload_result.metadata.get("creator") == "FoveaEngine Test Suite", "")

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_pass(name if detail.is_empty() else "%s — %s" % [name, detail])
	else:
		_fail(name, detail)

func _pass(detail: String) -> void:
	_passed += 1
	print("  ✓ %s" % detail)

func _fail(test_name: String, err: String) -> void:
	_failed += 1
	print("  ✗ %s — %s" % [test_name, err])
