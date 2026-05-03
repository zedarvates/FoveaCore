#[compute]
#version 450

// FoveaEngine: GPU Procedural Noise Generator
// Pre-computes FBM + Worley noise into a 3D texture for fast lookup.
// Replaces per-splat GDScript noise calls with a single texture sample.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// Output: 3D noise texture (R=FBM, G=Worley distance, B=Worley cell id)
layout(set = 0, binding = 0, rgba32f) uniform restrict writeonly image3D noise_texture;

layout(push_constant, std430) uniform Params {
    uint resolution;
    float noise_scale;
    float lacunarity;
    float gain;
    uint octaves;
    uint seed;
} params;

// --- Hash functions ---
uint hash(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

uint hash3(uvec3 p) {
    return hash(p.x ^ hash(p.y) ^ hash(p.z) ^ params.seed);
}

float hash_to_float(uint h) {
    return float(h) / float(0xFFFFFFFFU);
}

// Smoothstep for gradient smoothing
float smooth_noise(vec3 p) {
    ivec3 ip = ivec3(floor(p));
    vec3 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp);

    float n000 = hash_to_float(hash3(uvec3(ip)));
    float n100 = hash_to_float(hash3(uvec3(ip + ivec3(1, 0, 0))));
    float n010 = hash_to_float(hash3(uvec3(ip + ivec3(0, 1, 0))));
    float n110 = hash_to_float(hash3(uvec3(ip + ivec3(1, 1, 0))));
    float n001 = hash_to_float(hash3(uvec3(ip + ivec3(0, 0, 1))));
    float n101 = hash_to_float(hash3(uvec3(ip + ivec3(1, 0, 1))));
    float n011 = hash_to_float(hash3(uvec3(ip + ivec3(0, 1, 1))));
    float n111 = hash_to_float(hash3(uvec3(ip + ivec3(1, 1, 1))));

    return mix(
        mix(mix(n000, n100, fp.x), mix(n010, n110, fp.x), fp.y),
        mix(mix(n001, n101, fp.x), mix(n011, n111, fp.x), fp.y),
        fp.z
    );
}

// FBM (Fractional Brownian Motion)
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float max_value = 0.0;

    for (uint i = 0U; i < params.octaves; i++) {
        value += amplitude * smooth_noise(p * frequency);
        max_value += amplitude;
        frequency *= params.lacunarity;
        amplitude *= params.gain;
    }

    return value / max_value;
}

// Worley (Voronoi) noise — returns min distance
float worley(vec3 p) {
    ivec3 cell = ivec3(floor(p));
    float min_dist = 10.0;

    for (int dz = -1; dz <= 1; dz++) {
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                ivec3 neighbor = cell + ivec3(dx, dy, dz);
                vec3 point = vec3(neighbor) + hash_to_float(hash3(uvec3(neighbor)));
                float dist = length(p - point);
                min_dist = min(min_dist, dist);
            }
        }
    }

    return min_dist;
}

void main() {
    ivec3 texel = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(texel, ivec3(params.resolution)))) return;

    vec3 p = vec3(texel) / params.noise_scale;

    float fbm_val = fbm(p);
    float worley_dist = worley(p);
    float worley_cell = hash_to_float(hash3(uvec3(texel))) * 0.5;

    imageStore(noise_texture, texel, vec4(fbm_val, worley_dist, worley_cell, 1.0));
}
