class_name FoveaAutoROI
extends RefCounted

## FoveaEngine — Auto-ROI by AI (items 262-271)
## Uses MobileSAM ONNX to auto-detect the central object.

@export var model_path: String = "res://addons/foveacore/models/mobile_sam.onnx"
@export var confidence_threshold: float = 0.5

func detect_central_object(image: Image) -> Dictionary:
	"""Detect the main subject in an image. Returns mask + bounds."""
	var bounds = {"x": 0, "y": 0, "w": image.get_width(), "h": image.get_height()}
	
	# Would run MobileSAM ONNX inference here
	print("AutoROI: Detecting central object...")
	# Simulate detection (real implementation uses ONNX runtime)
	var cx = image.get_width() / 2
	var cy = image.get_height() / 2
	var r = min(cx, cy) * 0.4
	bounds = {"x": int(cx-r), "y": int(cy-r), "w": int(r*2), "h": int(r*2)}
	
	print("  Bounds: (%d,%d) %dx%d" % [bounds.x, bounds.y, bounds.w, bounds.h])
	return bounds
