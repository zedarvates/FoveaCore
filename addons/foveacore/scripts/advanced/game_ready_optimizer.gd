class_name GameReadyOptimizer
extends RefCounted

## FoveaEngine : Outil de Compression et d'Optimisation des Splats

const OPACITY_THRESHOLD = 0.05 # On supprime les splats avec < 5% d'opacité

## Convertit les complexes Harmoniques Sphériques (SH) en simples couleurs RGB
## Supprime 80% du poids des données couleurs pour les jeux vidéos.
static func bake_spherical_harmonics(splats: Array) -> Array:
    print("FoveaEngine: Baking Spherical Harmonics into Diffuse Colors...")
    for splat in splats:
        if splat.has("sh_features") and splat.sh_features.size() > 0:
            var base_sh = splat.sh_features[0]
            # Formule mathématique SH -> RGB : RGB = SH * 0.28209 + 0.5
            var r = clamp(base_sh.x * 0.28209 + 0.5, 0.0, 1.0)
            var g = clamp(base_sh.y * 0.28209 + 0.5, 0.0, 1.0)
            var b = clamp(base_sh.z * 0.28209 + 0.5, 0.0, 1.0)
            
            splat["color"] = Color(r, g, b, splat.get("opacity", 1.0))
            splat.erase("sh_features") # Libère la mémoire
    return splats

## Élimine les splats invisibles ou inutiles (Entropy Pruning)
static func prune_useless_splats(splats: Array) -> Array:
    var optimized_splats = []
    var culled_count = 0
    
    for splat in splats:
        # 1. Opacity Pruning
        if splat.get("opacity", 1.0) < OPACITY_THRESHOLD:
            culled_count += 1
            continue
            
        # 2. Scale Pruning (Supprime les splats microscopiques invisibles)
        var scale = splat.get("scale", Vector3.ZERO)
        if scale.length_squared() < 0.0001:
            culled_count += 1
            continue
            
        optimized_splats.append(splat)
        
    print("FoveaEngine: Pruned %d useless splats." % culled_count)
    return optimized_splats

## Calcule la "Normale" approximative depuis l'échelle et la rotation
static func precalculate_normals(splats: Array) -> Array:
    # À implémenter : Extraire l'axe le plus court (Z local) du quaternion de rotation
    # C'est cette normale qui sera écrite dans le fichier .fovea pour le Backface Culling
    pass
    return splats