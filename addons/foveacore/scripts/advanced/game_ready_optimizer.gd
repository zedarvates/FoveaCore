class_name GameReadyOptimizer
extends RefCounted

## FoveaEngine : Outil de Compression et d'Optimisation des Splats

const OPACITY_THRESHOLD = 0.05
const KMEANS_ITERATIONS = 10
const KMEANS_CONVERGENCE_THRESHOLD = 0.0001

## Convertit les complexes Harmoniques Sphériques (SH) en simples couleurs RGB
static func bake_spherical_harmonics(splats: Array) -> Array:
    print("FoveaEngine: Baking Spherical Harmonics into Diffuse Colors...")
    for splat in splats:
        if splat.has("sh_features") and splat.sh_features.size() > 0:
            var base_sh = splat.sh_features[0]
            var r = clamp(base_sh.x * 0.28209 + 0.5, 0.0, 1.0)
            var g = clamp(base_sh.y * 0.28209 + 0.5, 0.0, 1.0)
            var b = clamp(base_sh.z * 0.28209 + 0.5, 0.0, 1.0)
            splat["color"] = Color(r, g, b, splat.get("opacity", 1.0))
            splat.erase("sh_features")
    return splats

## Élimine les splats invisibles ou inutiles (Entropy Pruning)
static func prune_useless_splats(splats: Array) -> Array:
    var optimized_splats = []
    var culled_count = 0
    for splat in splats:
        if splat.get("opacity", 1.0) < OPACITY_THRESHOLD:
            culled_count += 1
            continue
        var scale = splat.get("scale", Vector3.ZERO)
        if scale.length_squared() < 0.0001:
            culled_count += 1
            continue
        optimized_splats.append(splat)
    print("FoveaEngine: Pruned %d useless splats." % culled_count)
    return optimized_splats

# ========================================================================
# PALETTE COLOR SYSTEM — Digital Painting optimisation
# ========================================================================

## Extrait toutes les couleurs uniques des splats
static func extract_colors(splats: Array) -> PackedColorArray:
    var colors := PackedColorArray()
    colors.resize(splats.size())
    for i in splats.size():
        var c: Color
        if splats[i] is Dictionary:
            c = splats[i].get("color", Color.WHITE)
        elif splats[i].has_method("get") and splats[i].get("color") != null:
            c = splats[i].color
        else:
            c = Color.WHITE
        colors[i] = Color(c.r, c.g, c.b)
    return colors

## Quantization K-means : reduit N couleurs a K centroides
static func kmeans_quantize(colors: PackedColorArray, k: int) -> FoveaColorPalette:
    if k < 2 or k > 256:
        push_error("k must be between 2 and 256")
        return null

    var n := colors.size()
    if n == 0:
        return null

    # --- Init centroids via k-means++ (meilleure distribution) ---
    var centroids := _init_centroids_kpp(colors, k)

    var palette := FoveaColorPalette.new()
    palette.palette_name = "K-means %d-color" % k
    palette.colors.resize(k)
    palette.palette_size = k

    var assignments := PackedInt32Array()
    assignments.resize(n)
    var cluster_counts := PackedInt32Array()
    cluster_counts.resize(k)

    for iter in KMEANS_ITERATIONS:
        # Reset
        for j in k:
            cluster_counts[j] = 0
            centroids[j] = Color.BLACK

        var changed := 0.0

        for i in n:
            var best_idx := _nearest_centroid(colors[i], centroids, k)
            assignments[i] = best_idx
            centroids[best_idx] += colors[i]
            cluster_counts[best_idx] += 1

        # Average & check convergence
        for j in k:
            if cluster_counts[j] > 0:
                var prev := centroids[j]
                centroids[j] = centroids[j] / float(cluster_counts[j])
                changed += (prev.r - centroids[j].r) * (prev.r - centroids[j].r) + \
                           (prev.g - centroids[j].g) * (prev.g - centroids[j].g) + \
                           (prev.b - centroids[j].b) * (prev.b - centroids[j].b)

        if changed < KMEANS_CONVERGENCE_THRESHOLD * k:
            break

    for j in k:
        palette.colors[j] = centroids[j]

    return palette

## Applique une palette aux splats (remplace chaque couleur par l'entree la plus proche)
static func apply_palette(splats: Array, palette: FoveaColorPalette) -> Array:
    if palette == null or palette.colors.is_empty():
        return splats

    var remapped := 0
    for i in splats.size():
        var splat = splats[i]
        var idx: int
        var c: Color
        if splat is Dictionary:
            c = splat.get("color", Color.WHITE)
            idx = palette.find_nearest(c)
            splat["color"] = palette.colors[idx]
            splat["palette_index"] = idx
        elif splat.has_method("set") or splat.get("color") != null:
            c = splat.color
            idx = palette.find_nearest(c)
            splat.color = palette.colors[idx]
        else:
            idx = 0
        remapped += 1

    print("FoveaEngine: Remapped %d splats to %d-color palette '%s'." % \
          [remapped, palette.colors.size(), palette.palette_name])
    return splats

## Full pipeline: extract + quantize + apply
static func build_and_apply_palette(splats: Array, k: int = 16) -> FoveaColorPalette:
    var colors := extract_colors(splats)
    var palette := kmeans_quantize(colors, k)
    apply_palette(splats, palette)
    return palette

# --- Internal helpers ---

static func _nearest_centroid(color: Color, centroids: Array, k: int) -> int:
    var best_idx := 0
    var best_dist := 1e9
    for j in k:
        var dc: Color = centroids[j]
        var d: float = (dc.r - color.r) * (dc.r - color.r) + \
                 (dc.g - color.g) * (dc.g - color.g) + \
                 (dc.b - color.b) * (dc.b - color.b)
        if d < best_dist:
            best_dist = d
            best_idx = j
    return best_idx

static func _init_centroids_kpp(colors: PackedColorArray, k: int) -> Array[Color]:
    # k-means++ initialization
    var n := colors.size()
    var centroids: Array[Color] = []
    centroids.resize(k)

    # First centroid = random
    centroids[0] = colors[randi() % n]

    for j in range(1, k):
        var total_weight := 0.0
        var weights := PackedFloat32Array()
        weights.resize(n)

        for i in n:
            var min_d2 := 1e9
            for m in j:
                var dc := centroids[m]
                var d2 := (dc.r - colors[i].r) * (dc.r - colors[i].r) + \
                          (dc.g - colors[i].g) * (dc.g - colors[i].g) + \
                          (dc.b - colors[i].b) * (dc.b - colors[i].b)
                if d2 < min_d2:
                    min_d2 = d2
            weights[i] = min_d2
            total_weight += min_d2

        # Pick next centroid weighted by distance^2
        var threshold := randf() * total_weight
        var cumulative := 0.0
        for i in n:
            cumulative += weights[i]
            if cumulative >= threshold:
                centroids[j] = colors[i]
                break

    return centroids

## Calcule la "Normale" approximative depuis l'échelle et la rotation
## L'axe le plus court (Z local) du quaternion de rotation = normale
static func precalculate_normals(splats: Array) -> Array:
    for splat in splats:
        var scale: Vector3 = splat.get("scale", Vector3.ONE)
        var rot: Quaternion = splat.get("rotation", Quaternion.IDENTITY)
        if scale.length_squared() < 0.0001:
            splat["normal"] = Vector3.UP
            continue
        var local_z := rot * Vector3.FORWARD
        var local_y := rot * Vector3.UP
        var local_x := rot * Vector3.RIGHT
        if scale.z < scale.x and scale.z < scale.y:
            splat["normal"] = local_z.normalized()
        elif scale.x < scale.y:
            splat["normal"] = local_x.normalized()
        else:
            splat["normal"] = local_y.normalized()
    return splats