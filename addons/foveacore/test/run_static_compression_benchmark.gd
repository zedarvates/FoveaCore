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

const DEFAULT_SOURCE_PATH := "res://test/fixtures/reference_3dgs.ply"
const DEFAULT_OUTPUT_PATH := "user://static_compression_reference.fovea"


func _init() -> void:
	var source_path: String = _argument_value("source", DEFAULT_SOURCE_PATH)
	var output_path: String = _argument_value("output", DEFAULT_OUTPUT_PATH)
	if not source_path.begins_with("res://") or source_path.get_extension().to_lower() != "ply":
		push_error("Static compression benchmark: --source must be a res:// .ply path")
		quit(1)
		return
	if not output_path.begins_with("user://") or output_path.get_extension().to_lower() != "fovea":
		push_error("Static compression benchmark: --output must be a user:// .fovea path")
		quit(1)
		return

	var source_values: Array = PLYLoaderScript.load_gaussians_from_ply(source_path)
	var source_splats: Array[GaussianSplat] = []
	for value: Variant in source_values:
		if value is GaussianSplat:
			source_splats.append(value)
	if source_splats.is_empty():
		push_error("Static compression benchmark: source fixture is empty")
		quit(1)
		return

	if not FoveaAssetWriterScript.write_fovea_asset(output_path, source_splats):
		push_error("Static compression benchmark: writer failed")
		quit(1)
		return

	var loaded: Variant = FoveaAssetLoaderScript.new()._load(output_path, "", false, 0)
	if not loaded is FoveaAsset:
		push_error("Static compression benchmark: generated asset did not reload")
		quit(1)
		return

	var encoded_bytes := FileAccess.get_file_as_bytes(output_path).size()
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


func _argument_value(name: String, default_value: String) -> String:
	var prefix: String = "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return default_value
