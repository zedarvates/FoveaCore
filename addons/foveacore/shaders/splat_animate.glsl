#[compute]
#version 450

// FoveaEngine : splat_animate.glsl (Section 2)
// Generic splat animation compute pass — applies flow, morph, stretch on GPU.
// Reads base splat buffer, writes animated splat buffer.
// Called before gpu_culling_compute to ensure culler sees animated positions.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index RGB565 (16 bits), covar_index (16 bits)
    uint data3; // opacity (8 bits), layer_id (8 bits), anim_flags (8 bits), padding (8 bits)
};

// Buffer 0: base splats (read-only, immutable)
layout(set = 0, binding = 0, std430) restrict readonly buffer BaseSplats {
    PackedSplat base_splats[];
};

// Buffer 1: animated splats (write-only, consumed by culler)
layout(set = 0, binding = 1, std430) restrict writeonly buffer AnimatedSplats {
    PackedSplat animated_splats[];
};

// Push constants updated each frame from FoveaAnimationSubsystem
layout(push_constant, std430) uniform AnimParams {
    float anim_time;
    float global_intensity;
    float amplitude;
    float frequency;
    uint anim_enabled;  // 0 = bypass, copy input → output unchanged
    uint total_splats;
    uint layer_mask;    // bitmask: which layers to animate (bit 0 = layer 0)
    float pad1;
} params;

// Fast noise hash for per-splat phase
uint hash_uint(uint x) {
    x = (x ^ 61u) ^ (x >> 16u);
    x = x + (x << 3u);
    x = x ^ (x >> 4u);
    x = x * 0x27d4eb2du;
    x = x ^ (x >> 15u);
    return x;
}

float hash_float(uint x) {
    return float(hash_uint(x)) / 4294967296.0;
}

// Unpack half-float pairs (matches delta_animation.glsl)
vec2 unpack_half_2(uint packed_val) {
    return unpackHalf2x16(packed_val);
}

uint pack_half_2(vec2 v) {
    return packHalf2x16(v);
}

// 3D simplex-like noise for curl flow
float noise_3d(vec3 p) {
    // Simple hash-based noise for GPU
    uint h = hash_uint(uint(p.x * 1000.0)) ^ 
             hash_uint(uint(p.y * 1000.0)) ^ 
             hash_uint(uint(p.z * 1000.0));
    return hash_float(h) * 2.0 - 1.0;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= params.total_splats) return;
    
    PackedSplat base = base_splats[idx];
    
    if (params.anim_enabled == 0u) {
        animated_splats[idx] = base;
        return;
    }
    
    // Unpack position (FP16 from data0, data1)
    vec3 pos = vec3(
        unpack_half_2(base.data0),
        0.0
    );
    float pos_z_f16 = float(base.data1 & 0xFFFFu);
    pos.z = pos_z_f16 / 65535.0 * 100.0 - 50.0; // Map 0-65535 → -50..+50
    
    // Check layer mask
    uint layer = (base.data3 >> 8u) & 0xFFu;
    bool layer_active = (params.layer_mask & (1u << layer)) != 0u;
    
    if (!layer_active) {
        animated_splats[idx] = base;
        return;
    }
    
    float t = params.anim_time;
    float intensity = params.global_intensity;
    float amp = params.amplitude;
    float freq = params.frequency;
    
    // Per-splat phase from hash
    float phase = hash_float(idx) * 6.283185307;
    
    // === ANIM_FLOW — Curl-noise displacement ===
    vec3 offset = vec3(0.0);
    float nx = sin(pos.x * freq + t * 0.5 + pos.y * 0.3) * cos(pos.z * freq * 0.7 + t * 0.3);
    float ny = cos(pos.y * freq + t * 0.4 + pos.z * 0.5) * sin(pos.x * freq * 0.7 + t * 0.3);
    float nz = sin(pos.z * freq + t * 0.6 + pos.x * 0.4) * cos(pos.y * freq * 0.7 + t * 0.5);
    
    // Divergence-free curl-like displacement
    offset.x = (ny - nz) * amp;
    offset.y = (nz - nx) * amp;
    offset.z = (nx - ny) * amp;
    
    // === ANIM_STRETCH — Log-space scale pulsation ===
    float stretch = 1.0 + sin(t + phase) * amp * 0.3;
    
    // === PULSATION — Non-uniform breathing ===
    float breathe_x = 1.0 + sin(t * 0.7 + phase) * amp * 0.2;
    float breathe_y = 1.0 + sin(t * 0.7 + phase + 2.094) * amp * 0.2;
    float breathe_z = 1.0 + sin(t * 0.7 + phase + 4.189) * amp * 0.2;
    
    // Apply offset to position
    vec3 new_pos = pos + offset * intensity;
    
    // Clamp to valid range
    new_pos = clamp(new_pos, vec3(-50.0), vec3(50.0));
    
    // Repack position
    PackedSplat anim = base;
    anim.data0 = pack_half_2(new_pos.xy);
    // For data1, keep normals from base, encode new Z position compressed
    uint z_enc = uint(clamp((new_pos.z + 50.0) / 100.0, 0.0, 1.0) * 65535.0);
    anim.data1 = (base.data1 & 0xFFFF0000u) | (z_enc & 0xFFFFu);
    
    // Set anim_active flag in data3 padding (bit 16, layer 2 nibble)
    anim.data3 = base.data3 | 0x10000u; // mark as animated
    
    animated_splats[idx] = anim;
}
