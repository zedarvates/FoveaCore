extends RefCounted
class_name SplatFormatLoader
## Unified entry point for loading Gaussian Splatting point clouds (Phase 1, Chantier J).
##
## Routes by file extension to the right parser, returning a typed
## [code]Array[GaussianSplat][/code]:
##   .ply  → [PLYLoader] (3DGS training output)
##   .splat→ binary 32-bytes/splat (antimatter15 / Luma / Polycam exports)   [J1]
##   .spz  → gzip-compressed quantized (Niantic)                              [J2 — TODO]
##   .sog  → WebP self-describing compressed (SOGS)                           [J3 — TODO]
##
## .fovea is handled natively by the resource loader, not here.

const GaussianSplat = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")
const _PlyLoaderScript = preload("res://addons/foveacore/scripts/reconstruction/ply_loader.gd")

## Number of bytes per splat in the binary .splat format.
const SPLAT_STRIDE := 32


## Loads a splat cloud from [param path], routing by extension. Returns an empty
## array (and pushes an error/warning) on unsupported or unreadable input.
static func load_gaussians(path: String) -> Array[GaussianSplat]:
	match path.get_extension().to_lower():
		"ply":
			return _PlyLoaderScript.load_gaussians_from_ply(path)
		"splat":
			return load_splat(path)
		"spz":
			push_warning("SplatFormatLoader: .spz not yet supported (Phase 1, J2).")
			return []
		"sog":
			push_warning("SplatFormatLoader: .sog not yet supported (Phase 1, J3).")
			return []
		_:
			push_error("SplatFormatLoader: unsupported splat format: " + path)
			return []


## True if [param path] has an extension this loader (eventually) handles.
static func is_supported(path: String) -> bool:
	return path.get_extension().to_lower() in ["ply", "splat", "spz", "sog"]


## Parses the binary [code].splat[/code] format: 32 bytes per splat —
## position (3×f32), scale (3×f32, absolute), color RGBA (4×u8), rotation
## (4×u8 quaternion, w,x,y,z, each (b-128)/128). Little-endian.
static func load_splat(path: String) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []

	if not FileAccess.file_exists(path):
		push_error("SplatFormatLoader: file not found: " + path)
		return splats

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SplatFormatLoader: cannot open: " + path)
		return splats

	var size := f.get_length()
	if size == 0 or size % SPLAT_STRIDE != 0:
		push_error("SplatFormatLoader: .splat size %d is not a multiple of %d (corrupt?)" % [size, SPLAT_STRIDE])
		f.close()
		return splats

	var count := int(size / SPLAT_STRIDE)
	for _i in range(count):
		var s := GaussianSplat.new(Vector3(f.get_float(), f.get_float(), f.get_float()))
		s.scale = Vector3(f.get_float(), f.get_float(), f.get_float())  # absolute, not log-space

		var r := f.get_8()
		var g := f.get_8()
		var b := f.get_8()
		var a := f.get_8()
		s.opacity = a / 255.0
		s.color = Color(r / 255.0, g / 255.0, b / 255.0, s.opacity)

		# Rotation: 4 × uint8 → quaternion (w, x, y, z), each (byte - 128) / 128.
		var qw := (f.get_8() - 128) / 128.0
		var qx := (f.get_8() - 128) / 128.0
		var qy := (f.get_8() - 128) / 128.0
		var qz := (f.get_8() - 128) / 128.0
		var q := Quaternion(qx, qy, qz, qw)
		if q.length_squared() > 0.0001:
			s.rotation = q.normalized()

		s.compute_derived()
		splats.append(s)

	f.close()
	print("SplatFormatLoader: loaded %d splats from .splat" % splats.size())
	return splats
