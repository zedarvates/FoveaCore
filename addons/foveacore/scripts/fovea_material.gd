extends Resource
## FoveaMaterial - Définition d'un matériau procédural pour FoveaCore
## Remplace les matériaux PBR traditionnels par des paramètres procéduraux

class_name FoveaMaterial

## Type de matériau
enum MaterialType {
	STONE,
	WOOD,
	METAL,
	SKIN,
	FABRIC,
	GLASS,
	CUSTOM
}

@export var material_type := MaterialType.STONE
@export var base_color := Color(0.5, 0.5, 0.5)
@export_range(0.0, 1.0) var roughness := 0.8
@export_range(0.0, 1.0) var metallic := 0.0
@export_range(0.0, 1.0) var bump_strength := 0.5
@export_range(0.0, 1.0) var specular_strength := 0.3

## Paramètres spécifiques au type
@export var noise_scale := 10.0
@export var noise_octaves := 4
@export var noise_lacunarity := 2.0
@export var noise_gain := 0.5
