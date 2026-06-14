@tool
class_name FoveaMultiMeshBulk
extends RefCounted

## Écritures bulk MultiMesh (règle CLAUDE.md « Batch Processing »).
## Remplace les boucles set_instance_transform()/set_instance_color() par
## une seule affectation de `multimesh.buffer` (PackedFloat32Array).
## Gain attendu : 10x à 50x sur les mises à jour massives.
##
## Layout par instance (TRANSFORM_3D) :
##   12 floats transform (lignes de la matrice 3x4)
##   [+ 4 floats color si use_colors]
##   [+ 4 floats custom_data si use_custom_data]


## Nombre de floats par instance selon la configuration du MultiMesh.
static func stride_of(mm: MultiMesh) -> int:
	var s: int = 12
	if mm.use_colors:
		s += 4
	if mm.use_custom_data:
		s += 4
	return s


## Écrit un Transform3D à l'offset `base` (layout RenderingServer, lignes 3x4).
static func write_transform(buf: PackedFloat32Array, base: int, xf: Transform3D) -> void:
	var b: Basis = xf.basis
	var o: Vector3 = xf.origin
	buf[base + 0] = b.x.x
	buf[base + 1] = b.y.x
	buf[base + 2] = b.z.x
	buf[base + 3] = o.x
	buf[base + 4] = b.x.y
	buf[base + 5] = b.y.y
	buf[base + 6] = b.z.y
	buf[base + 7] = o.y
	buf[base + 8] = b.x.z
	buf[base + 9] = b.y.z
	buf[base + 10] = b.z.z
	buf[base + 11] = o.z


## Écrit une Color (4 floats) à l'offset `base` (= base_instance + 12 si use_colors).
static func write_color(buf: PackedFloat32Array, base: int, color: Color) -> void:
	buf[base + 0] = color.r
	buf[base + 1] = color.g
	buf[base + 2] = color.b
	buf[base + 3] = color.a


## Applique `count` transforms en une seule écriture GPU.
## Préserve les couleurs/custom data déjà présentes dans le buffer.
static func set_transforms(mm: MultiMesh, transforms: Array[Transform3D], count: int = -1) -> void:
	if mm == null or mm.instance_count == 0:
		return
	var n: int = mini(mm.instance_count, transforms.size())
	if count >= 0:
		n = mini(n, count)
	var stride: int = stride_of(mm)
	var buf: PackedFloat32Array = mm.buffer
	for i in n:
		write_transform(buf, i * stride, transforms[i])
	mm.buffer = buf
