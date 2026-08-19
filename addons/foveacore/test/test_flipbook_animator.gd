extends SceneTree

const FlipbookAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_flipbook_animator.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const FoveaAssetWriterScript = preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")

const FLIPBOOK_FOLDER := "user://fovea_flipbook_fixture"

func _init() -> void:

	var animator: FoveaFlipbookAnimator = FlipbookAnimator.new()
	var active: GaussianSplat = GaussianSplatScript.new()
	active.flipbook_frame = 0
	active.flipbook_frame_count = 2
	var inactive: GaussianSplat = GaussianSplatScript.new()
	inactive.flipbook_frame = 1
	inactive.flipbook_frame_count = 2
	animator._apply_to_splat(active, 0.0, 1.0)
	animator._apply_to_splat(inactive, 0.0, 1.0)
	assert(active.opacity > 0.0)
	assert(is_zero_approx(inactive.opacity))

	# Test FoveaAssetFormatLoader.load_flipbook_folder with two valid native frames.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FLIPBOOK_FOLDER))
	var frame_a: GaussianSplat = GaussianSplatScript.new(Vector3.ZERO)
	var frame_b: GaussianSplat = GaussianSplatScript.new(Vector3.ONE)
	assert(FoveaAssetWriterScript.write_fovea_asset(
		FLIPBOOK_FOLDER.path_join("frame_000.fovea"), [frame_a]))
	assert(FoveaAssetWriterScript.write_fovea_asset(
		FLIPBOOK_FOLDER.path_join("frame_001.fovea"), [frame_b]))
	var assets: Array[FoveaAsset] = FoveaAssetFormatLoader.load_flipbook_folder(FLIPBOOK_FOLDER)
	assert(assets.size() == 2)
	assert(assets[0].flipbook_frame == 0)
	assert(assets[1].flipbook_frame == 1)
	assert(assets[0].flipbook_frame_count == 2)

	print("PASS: flipbook selects exactly the active frame and loads sequence folder")
	assets.clear()
	animator.free()
	active = null
	inactive = null
	frame_a = null
	frame_b = null
	await process_frame
	quit(0)
