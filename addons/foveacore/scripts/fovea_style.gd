extends Resource
## FoveaStyle - Ressource définissant un style visuel procédural ou neural
## Utilisé par le Style Engine pour générer la "pâte" visuelle des matériaux

class_name FoveaStyle

## Mode de style
@export var mode := "procedural" # "procedural" ou "neural"

## Paramètres procéduraux
@export_group("Procedural Parameters")
@export_range(0.0, 2.0) var detail := 1.0
@export_range(0.0, 1.0) var grain := 0.5
@export_range(0.0, 1.0) var light_coherence := 0.8
@export_range(0.0, 1.0) var color_saturation := 0.7
@export_range(0.0, 1.0) var micro_shadow := 0.5

## Paramètres neuronaux (optionnel)
@export_group("Neural Parameters")
@export var lora_path := "" # Chemin vers le fichier LoRA
@export_range(0.0, 1.0) var neural_strength := 0.0
@export var temporal_coherence := true

## Paramètres matériaux
@export_group("Material Overrides")
@export var stone_params: FoveaMaterial = null
@export var wood_params: FoveaMaterial = null
@export var metal_params: FoveaMaterial = null
@export var skin_params: FoveaMaterial = null

func _init():
	mode = "procedural"
	detail = 1.0
	grain = 0.5
	light_coherence = 0.8
