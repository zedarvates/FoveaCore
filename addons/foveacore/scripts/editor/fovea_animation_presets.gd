class_name FoveaAnimationPresets
extends Resource
@export var preset_name: String = "Custom"
@export var color_amplitude: float = 0.1
@export var opacity_amplitude: float = 0.2
@export var emission_amplitude: float = 0.3
@export var frequency: float = 1.5
@export var base_color: Color = Color.WHITE
@export var target_color: Color = Color(0.5, 0.5, 1.0, 1.0)
@export var description: String = ""
const BUILT_IN: Dictionary = {
	"Living Watercolor": {"color_amplitude": 0.15, "opacity_amplitude": 0.1, "emission_amplitude": 0.0, "frequency": 0.8, "base_color": Color(0.8, 0.7, 0.9), "target_color": Color(0.5, 0.4, 0.8)},
	"Pulsing Metal": {"color_amplitude": 0.05, "opacity_amplitude": 0.0, "emission_amplitude": 0.5, "frequency": 2.0, "base_color": Color(0.6, 0.5, 0.4), "target_color": Color(1.0, 0.3, 0.1)},
	"Breathing Wood": {"color_amplitude": 0.03, "opacity_amplitude": 0.05, "emission_amplitude": 0.0, "frequency": 0.3, "base_color": Color(0.5, 0.35, 0.2), "target_color": Color(0.6, 0.45, 0.3)},
	"Alien Bioluminescence": {"color_amplitude": 0.2, "opacity_amplitude": 0.3, "emission_amplitude": 0.8, "frequency": 1.2, "base_color": Color(0.0, 0.5, 0.3), "target_color": Color(0.0, 1.0, 0.5)},
	"Flickering Flame": {"color_amplitude": 0.25, "opacity_amplitude": 0.3, "emission_amplitude": 0.9, "frequency": 4.0, "base_color": Color(0.9, 0.3, 0.0), "target_color": Color(1.0, 0.8, 0.0)},
}
func apply_to(mat_osc) -> void:
	mat_osc.color_amplitude = color_amplitude; mat_osc.opacity_amplitude = opacity_amplitude
	mat_osc.emission_amplitude = emission_amplitude; mat_osc.frequency = frequency
	mat_osc.base_color = base_color; mat_osc.target_color = target_color
