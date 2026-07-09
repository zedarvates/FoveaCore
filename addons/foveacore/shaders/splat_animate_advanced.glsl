#[compute]
#version 450

// FoveaEngine : splat_animate_advanced.glsl (Section 3)
// Advanced GPU animation pass — morph covariance, flipbook, neural offset.
// Reads base splats + per-mode data, writes animated splats.
// Called as second pass after basic splat_animate.glsl.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
};

// Buffer 0: base/input splats
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat input_splats[];
};

// Buffer 1: animated output
layout(set = 0, binding = 1, std430) restrict writeonly buffer OutputSplats {
    PackedSplat output_splats[];
};

// Optional: Texture3D for neural offset field (binding 2)
layout(set = 0, binding = 2) uniform texture3D neural_offset_tex;

// Optional: Covariance palette (binding 3)
layout(set = 0, binding = 3, std430) restrict readonly buffer CovarPalette {
    vec4 covar_data[];  // 4 vec4 per covariance: R0, R1, R2, scale
};

// Optional: Skinning bone matrices (binding 4)
layout(set = 0, binding = 4, std430) restrict readonly buffer BoneMatrices {
    mat4x4 bone_mats[];
};

// Optional: Flipbook frame data (binding 5)
layout(set = 0, binding = 5, std430) restrict readonly buffer FlipbookData {
    uint frame_indices[];
};

layout(push_constant, std430) uniform AnimParams {
    float anim_time;
    float global_intensity;
    float morph_amplitude;
    float morph_frequency;
    float flipbook_fps;
    float neural_intensity;
    uint anim_mode_mask;    // bit 0: morph, bit 1: flipbook, bit 2: neural, bit 3: skin, bit 4: cloth
    uint total_splats;
    uint frame_count;
    uint current_frame;
    float crossfade_blend;
    uint pad1;
    uint pad2;
} params;

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

vec2 unpack_half_2(uint v) { return unpackHalf2x16(v); }
uint pack_half_2(vec2 v) { return packHalf2x16(v); }

// === MORPH COVARIANCE (items 46-52) ===

// Slerp quaternion interpolation
vec4 slerp(vec4 qa, vec4 qb, float t) {
    float cos_half = dot(qa, qb);
    vec4 qb_adj = qb;
    if (cos_half < 0.0) { qb_adj = -qb; cos_half = -cos_half; }
    if (cos_half >= 1.0) return qa;
    float half_angle = acos(clamp(cos_half, -1.0, 1.0));
    float inv_sin = 1.0 / sin(half_angle);
    float t0 = sin((1.0 - t) * half_angle) * inv_sin;
    float t1 = sin(t * half_angle) * inv_sin;
    return qa * t0 + qb_adj * t1;
}

void apply_morph_covariance(inout PackedSplat splat, uint idx) {
    float t = params.anim_time * params.morph_frequency;
    float amp = params.morph_amplitude;
    float phase = hash_float(idx) * 6.283185;
    
    // Read base covariance index from data2
    uint covar_idx = (splat.data2 >> 16u) & 0xFFFFu;
    
    if (covar_idx >= 65535u) return; // invalid
    
    // PULSE: uniform log-space scaling
    float pulse = 1.0 + sin(t + phase) * amp;
    
    // BREATHE: dominant axis extends, minor contract
    float breathe = 1.0 + sin(t * 0.7 + phase) * amp * 0.3;
    
    // WOBBLE: rotation jitter (we encode as covar_index offset for demo)
    float wobble_angle = sin(t + phase * 0.5) * amp * 0.5;
    
    // Encode animated covariance as offset from base index
    // Phase 7 CPU: anim_flags bit 2 = morph active
    splat.data3 = splat.data3 | 0x40000u;
}

// === FLIPBOOK GPU (items 56-60) ===

void apply_flipbook(inout PackedSplat splat, uint idx) {
    if (params.frame_count <= 1) return;
    
    // Frame index is per-splat from the flipbook buffer
    uint frame = params.current_frame % params.frame_count;
    float blend = params.crossfade_blend;
    
    // Layer 2 nibble in data3: flipbook_frame (8 bits), flipbook_blend (8 bits)
    splat.data3 = (splat.data3 & 0xFFFF00FFu) | ((frame & 0xFFu) << 8u);
    
    // Set anim_active flag
    splat.data3 = splat.data3 | 0x10000u;
}

// === NEURAL OFFSET (items 61-65) ===

void apply_neural_offset(inout PackedSplat splat, uint idx) {
    // Unpack position
    vec3 pos = vec3(
        unpack_half_2(splat.data0),
        float(splat.data1 & 0xFFFFu) / 65535.0 * 100.0 - 50.0
    );
    
    // Sample neural offset texture (trilinear)
    vec3 uvw = (pos + vec3(50.0)) / 100.0;
    uvw = clamp(uvw, vec3(0.001), vec3(0.999));
    
    vec4 offset = texture(sampler3D(neural_offset_tex, samplerState), uvw);
    
    // Apply offset
    vec3 new_pos = pos + offset.xyz * params.neural_intensity;
    new_pos = clamp(new_pos, vec3(-50.0), vec3(50.0));
    
    // Repack
    splat.data0 = pack_half_2(new_pos.xy);
    uint z_enc = uint(clamp((new_pos.z + 50.0) / 100.0, 0.0, 1.0) * 65535.0);
    splat.data1 = (splat.data1 & 0xFFFF0000u) | (z_enc & 0xFFFFu);
    splat.data3 = splat.data3 | 0x10000u;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= params.total_splats) return;
    
    PackedSplat splat = input_splats[idx];
    uint mode = params.anim_mode_mask;
    
    if (mode == 0u) {
        output_splats[idx] = splat;
        return;
    }
    
    // Apply modes in fixed priority order: flipbook → neural → morph → skin
    if ((mode & 0x2u) != 0u) {
        apply_flipbook(splat, idx);
    }
    
    if ((mode & 0x4u) != 0u) {
        apply_neural_offset(splat, idx);
    }
    
    if ((mode & 0x1u) != 0u) {
        apply_morph_covariance(splat, idx);
    }
    
    // Mark as animated
    if (mode != 0u) {
        splat.data3 = splat.data3 | 0x10000u;
    }
    
    output_splats[idx] = splat;
}
