## TriangleSplatMesh - Générateur de maillage triangle pour Gaussian Splats
## Remplace les quads par un maillage triangulaire approximant l'ellipse
## Réduit drastiquement le coût du fragment shader

extends RefCounted
class_name TriangleSplatMesh

const SPLAT_SUBDIVISIONS = 16  # Nombre de segments pour l'ellipse (16 = bon compromis)

## Génère un maillage triangle pour un splat elliptique
static func generate_triangle_splat_mesh() -> ArrayMesh:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Centre du splat (sommet central pour fan triangulaire)
	# On utilise un sommet central pour simplifier le vertex shader
	surface_tool.set_normal(Vector3(0, 0, 1))
	surface_tool.set_uv(Vector2(0.5, 0.5))  # UV centre
	surface_tool.add_vertex(Vector3(0, 0, 0))
	
	# Générer les sommets sur le cercle unité
	var angle_step = 2.0 * PI / SPLAT_SUBDIVISIONS
	
	for i in range(SPLAT_SUBDIVISIONS + 1):
		var angle = i * angle_step
		var x = cos(angle)
		var y = sin(angle)
		
		# UV radial (utilisé pour le calcul de distance dans le fragment shader si besoin)
		var uv = Vector2((x + 1.0) * 0.5, (y + 1.0) * 0.5)
		surface_tool.set_normal(Vector3(0, 0, 1))
		surface_tool.set_uv(uv)
		surface_tool.add_vertex(Vector3(x, y, 0))
		
		# Créer les triangles du fan
		if i > 0:
			# Triangle: centre, sommet précédent, sommet courant
			surface_tool.add_index(0)
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
	
	# Dernier triangle pour fermer le cercle
	surface_tool.add_index(0)
	surface_tool.add_index(SPLAT_SUBDIVISIONS + 1)
	surface_tool.add_index(1)
	
	surface_tool.generate_normals()
	
	var mesh = surface_tool.commit()
	return mesh

## Génère un maillage triangle optimisé (sans sommet central, utilisation de STRIP)
static func generate_triangle_splat_mesh_optimized() -> ArrayMesh:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var angle_step = 2.0 * PI / SPLAT_SUBDIVISIONS
	var vertices = []
	
	# Générer les sommets sur le cercle unité
	for i in range(SPLAT_SUBDIVISIONS):
		var angle = i * angle_step
		var x = cos(angle)
		var y = sin(angle)
		vertices.append(Vector3(x, y, 0))
	
	# Créer des triangles en éventail depuis le centre implicite
	for i in range(SPLAT_SUBDIVISIONS):
		var next_i = (i + 1) % SPLAT_SUBDIVISIONS
		
		# Triangle 1: centre (0,0), sommet i, sommet i+1
		# Sommet centre
		surface_tool.set_normal(Vector3(0, 0, 1))
		surface_tool.set_uv(Vector2(0.5, 0.5))
		surface_tool.add_vertex(Vector3(0, 0, 0))
		
		# Sommet i
		var angle_i = i * angle_step
		var uv_i = Vector2((cos(angle_i) + 1.0) * 0.5, (sin(angle_i) + 1.0) * 0.5)
		surface_tool.set_normal(Vector3(0, 0, 1))
		surface_tool.set_uv(uv_i)
		surface_tool.add_vertex(vertices[i])
		
		# Sommet i+1
		var angle_next = next_i * angle_step
		var uv_next = Vector2((cos(angle_next) + 1.0) * 0.5, (sin(angle_next) + 1.0) * 0.5)
		surface_tool.set_normal(Vector3(0, 0, 1))
		surface_tool.set_uv(uv_next)
		surface_tool.add_vertex(vertices[next_i])
	
	surface_tool.generate_normals()
	var mesh = surface_tool.commit()
	return mesh