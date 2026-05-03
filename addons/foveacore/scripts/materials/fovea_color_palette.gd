class_name FoveaColorPalette
extends Resource

const DEFAULT_PALETTE_NAME := "Standard 16-color Watercolor"

## 16 couleurs "Digital Painting" optimisees pour blending additif
static func watercolor_16() -> FoveaColorPalette:
	var p = FoveaColorPalette.new()
	p.palette_name = DEFAULT_PALETTE_NAME
	p.colors = [
		Color(0.05, 0.05, 0.08),   # 0  ombre profonde / noir bleute
		Color(0.25, 0.22, 0.20),   # 1  terre sombre / sepia
		Color(0.45, 0.35, 0.25),   # 2  ocre / bois
		Color(0.60, 0.55, 0.45),   # 3  sable / pierre claire
		Color(0.88, 0.85, 0.78),   # 4  blanc chaud / ivoire
		Color(0.70, 0.25, 0.20),   # 5  rouge brique
		Color(0.90, 0.55, 0.25),   # 6  orange terre
		Color(0.95, 0.82, 0.35),   # 7  ocre jaune / lumiere
		Color(0.25, 0.45, 0.30),   # 8  vert foret
		Color(0.35, 0.60, 0.35),   # 9  vert feuillage
		Color(0.50, 0.70, 0.40),   # 10 vert olive clair
		Color(0.15, 0.35, 0.50),   # 11 bleu acier / ombre fresque
		Color(0.20, 0.30, 0.55),   # 12 bleu profond
		Color(0.45, 0.55, 0.70),   # 13 bleu cendre / ciel couvert
		Color(0.40, 0.30, 0.45),   # 14 violet terreux / lavande ombre
		Color(0.60, 0.50, 0.60),   # 15 mauve / gris colore
	]
	return p


static func grayscale_4() -> FoveaColorPalette:
	var p = FoveaColorPalette.new()
	p.palette_name = "4-color Grayscale"
	p.colors = [
		Color(0.05, 0.05, 0.05),
		Color(0.35, 0.35, 0.35),
		Color(0.65, 0.65, 0.65),
		Color(0.95, 0.95, 0.95),
	]
	return p


## Palette custom generee par K-means
@export var palette_name: String = "Custom Palette"
@export var colors: Array[Color] = []
@export var palette_size: int = 16:
	set(v):
		palette_size = v
		colors.resize(clamp(v, 2, 256))


func get_color(index: int) -> Color:
	if index < 0 or index >= colors.size():
		return Color.BLACK
	return colors[index]


func find_nearest(target: Color) -> int:
	var best_idx := 0
	var best_dist := 1e9
	for i in colors.size():
		var d = colors[i].r - target.r
		var d2 = colors[i].g - target.g
		var d3 = colors[i].b - target.b
		var dist = d * d + d2 * d2 + d3 * d3
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx


func to_packed_rgb_array() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(colors.size() * 4)
	for i in colors.size():
		var c := colors[i]
		data.encode_u8(i * 4 + 0, int(clamp(c.r * 255.0, 0, 255)))
		data.encode_u8(i * 4 + 1, int(clamp(c.g * 255.0, 0, 255)))
		data.encode_u8(i * 4 + 2, int(clamp(c.b * 255.0, 0, 255)))
		data.encode_u8(i * 4 + 3, 255)
	return data
