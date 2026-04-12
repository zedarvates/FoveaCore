# fovea_proxy_manager.gd
# Godot 4.x script for managing proxy reconstruction with foveated rendering
# Integrates ProxyFaceRenderer with FoveaXRInitializer to dynamically adjust
# reconstruction density based on foveal zone and distance.

extends Node
class_name FoveaProxyManager

## FoveaProxyManager — Coordinates proxy reconstruction with foveated rendering
## 
## This manager bridges the gap between:
## - ProxyFaceRenderer: Handles simplified mesh representation
## - FoveaXRInitializer: Manages OpenXR foveation settings
## 
## It dynamically adjusts reconstruction density based on:
## - Gaze direction (foveal zone)
## - Distance to objects
## - Current foveation level

signal density_changed(new_density: float)
signal proxy_state_changed(is_proxy_active: bool)

# References
var _proxy_renderer: ProxyFaceRenderer = null
var _xr_initializer: FoveaXRInitializer = null
var _xr_camera: XRCamera3D = null

# Configuration
@export_group("Density Control")
@export var enable_density_scaling: bool = true
@export var min_reconstruction_density: float = 0.1  # 10% - peripheral vision
@export var max_reconstruction_density: float = 1.0   # 100% - foveal vision
@export var density_falloff_distance: float = 10.0    # Distance where density starts falling
@export var foveal_zone_angle: float = 30.0            # Degrees from gaze center

# State
var _current_density: float = 1.0
var _target_density: float = 1.0
var _is_proxy_active: bool = false

func _ready() -> void:
	# Find and connect to required nodes
	_find_nodes()
	
	if _proxy_renderer and _xr_initializer:
		_connect_signals()
		print("FoveaProxyManager: Initialized successfully")
	else:
		push_warning("FoveaProxyManager: Missing dependencies - manual setup may be required")

func _find_nodes() -> void:
	# Try to find ProxyFaceRenderer in parent or siblings
	var parent = get_parent()
	_proxy_renderer = parent.get_node_or_null("ProxyFaceRenderer") as ProxyFaceRenderer
	
	# Try to find FoveaXRInitializer
	_xr_initializer = parent.get_node_or_null("FoveaXRInitializer") as FoveaXRInitializer
	
	# Try to find XRCamera3D
	_xr_camera = parent.get_node_or_null("XRCamera3D") as XRCamera3D

func _connect_signals() -> void:
	if _xr_initializer:
		_xr_initializer.xr_started.connect(_on_xr_started)
		_xr_initializer.xr_failed.connect(_on_xr_failed)
	
	# If proxy renderer has signals, connect them
	if _proxy_renderer and _proxy_renderer.has_signal("proxy_visibility_changed"):
		_proxy_renderer.proxy_visibility_changed.connect(_on_proxy_visibility_changed)

func _process(delta: float) -> void:
	if not enable_density_scaling:
		return
	
	_update_density_based_on_foveation(delta)

func _update_density_based_on_foveation(delta: float) -> void:
	if not _xr_camera or not _xr_initializer:
		return
	
	# Get current foveation level from XR initializer
	var foveation_level = _xr_initializer.foveation_level
	
	# Calculate density based on foveation level
	# Level 0 (None) = 100% density
	# Level 1 (Low) = 70% density in peripheral
	# Level 2 (Med) = 50% density in peripheral
	# Level 3 (High) = 30% density in peripheral
	var base_density = 1.0
	match foveation_level:
		0: base_density = 1.0
		1: base_density = 0.7
		2: base_density = 0.5
		3: base_density = 0.3
	
	# Adjust based on distance if proxy is active
	if _is_proxy_active and _proxy_renderer:
		var distance = _get_proxy_distance()
		var distance_factor = clamp(distance / density_falloff_distance, 0.0, 1.0)
		_target_density = lerp(max_reconstruction_density, min_reconstruction_density, distance_factor)
	else:
		_target_density = base_density
	
	# Smooth the density transition
	_current_density = lerp(_current_density, _target_density, delta * 2.0)
	
	# Emit signal for systems that need to adjust reconstruction
	if abs(_current_density - _target_density) > 0.01:
		density_changed.emit(_current_density)

func _get_proxy_distance() -> float:
	if not _xr_camera or not _proxy_renderer:
		return 0.0
	
	var cam_pos = _xr_camera.global_transform.origin
	var proxy_pos = _proxy_renderer.global_transform.origin
	return cam_pos.distance_to(proxy_pos)

# Signal handlers
func _on_xr_started() -> void:
	print("FoveaProxyManager: XR session started")
	enable_density_scaling = true

func _on_xr_failed(reason: String) -> void:
	print("FoveaProxyManager: XR failed - ", reason)
	enable_density_scaling = false

func _on_proxy_visibility_changed(is_visible: bool) -> void:
	_is_proxy_active = is_visible
	proxy_state_changed.emit(is_visible)

# Public API for external control
func set_reconstruction_density(density: float) -> void:
	_current_density = clamp(density, min_reconstruction_density, max_reconstruction_density)
	density_changed.emit(_current_density)

func get_current_density() -> float:
	return _current_density

func is_proxy_mode_active() -> bool:
	return _is_proxy_active