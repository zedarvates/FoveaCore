extends SceneTree

const PLYLoaderScript := preload(
	"res://addons/foveacore/scripts/reconstruction/ply_loader.gd"
)
const FoveaAssetWriterScript := preload(
	"res://addons/foveacore/scripts/fovea_asset_writer.gd"
)
const FoveaAssetLoaderScript := preload(
	"res://addons/foveacore/scripts/fovea_asset_loader.gd"
)
const StaticCompressionBenchmarkScript := preload(
	"res://addons/foveacore/scripts/reconstruction/static_compression_benchmark.gd"
)

const SOURCE_PATH := "res://test/fixtures/reference_3dgs.ply"
const OUTPUT_PATH := "user://static_compression_reference.fovea"


func _init() -> void:
	var source_values: Array = PLYLoaderScript.load_gaussians_from_ply(SOURCE_PATH)
	var source_splats: Array[GaussianSplat] = []
	for value: Variant in source_values:
		if value is GaussianSplat:
			source_splats.append(value)
	if source_splats.is_empty():
		push_error("Static compression benchmark: source fixture is empty")
		quit(1)
		return

	if not FoveaAssetWriterScript.write_fovea_asset(OUTPUT_PATH, source_splats):
		push_error("Static compression benchmark: writer failed")
		quit(1)
		return

	var loaded: Variant = FoveaAssetLoaderScript.new()._load(OUTPUT_PATH, "", false, 0)
	if not loaded is FoveaAsset:
		push_error("Static compression benchmark: generated asset did not reload")
		quit(1)
		return

	var encoded_bytes := FileAccess.get_file_as_bytes(OUTPUT_PATH).size()
	var report: Dictionary = StaticCompressionBenchmarkScript.analyze(
		source_splats,
		loaded as FoveaAsset,
		encoded_bytes
	)
	if not bool(report.get("ok", false)):
		push_error("Static compression benchmark: %s" % str(report.get("error", "unknown error")))
		quit(1)
		return

	print("STATIC_COMPRESSION_REPORT=%s" % JSON.stringify(report["metrics"]))
	quit(0)
