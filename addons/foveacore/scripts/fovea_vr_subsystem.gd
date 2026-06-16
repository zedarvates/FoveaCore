class_name FoveaVRSubsystem
extends Node

## FoveaVRSubsystem — Gestion isolée de l'interface OpenXR.
## Extrait de FoveaCoreManager pour respecter le principe de responsabilité unique.
## Responsabilités :
##   - Initialisation OpenXR au démarrage
##   - Exposition de l'état XR (actif, shader activé)
##   - Pas de logique de rendu splat

## Signal émis quand OpenXR est initialisé avec succès
signal xr_initialized
## Signal émis si OpenXR n'est pas disponible
signal xr_unavailable(reason: String)

@export var vr_enabled: bool = true
@export var xr_shader_enabled: bool = true

## true si OpenXR est actif et prêt
var is_xr_active: bool = false

func setup(enabled: bool, shader: bool) -> void:
	vr_enabled = enabled
	xr_shader_enabled = shader
	if vr_enabled:
		_initialize_openxr()

func _initialize_openxr() -> void:
	print("FoveaVRSubsystem: Enabling OpenXR 1.0+ Integration...")
	var xr_interface: XRInterface = XRServer.find_interface("OpenXR")
	if not xr_interface:
		push_warning("FoveaVRSubsystem: No OpenXR interface found.")
		xr_unavailable.emit("No OpenXR interface found")
		return

	if not xr_interface.is_initialized():
		if xr_interface.initialize():
			_activate_xr()
		else:
			push_warning("FoveaVRSubsystem: Failed to initialize OpenXR.")
			xr_unavailable.emit("OpenXR initialization failed")
	else:
		_activate_xr()

func _activate_xr() -> void:
	get_viewport().use_xr = true
	ProjectSettings.set_setting("xr/shaders/enabled", xr_shader_enabled)
	is_xr_active = true
	print("FoveaVRSubsystem: OpenXR active. XR Shader: ", xr_shader_enabled)
	xr_initialized.emit()
