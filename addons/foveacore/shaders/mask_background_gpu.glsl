#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform readonly image2D input_image;
layout(set = 0, binding = 1, r8) uniform writeonly image2D output_mask;

layout(push_constant) uniform Params {
	float threshold;
	int mask_mode;
	int roi_x;
	int roi_y;
	int roi_w;
	int roi_h;
} pc;

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(input_image);
	
	if (uv.x >= size.x || uv.y >= size.y) {
		return;
	}

	vec4 color = imageLoad(input_image, uv);
	float mask_val = 1.0;

	// ROI Check
	if (pc.roi_w > 0 && pc.roi_h > 0) {
		if (uv.x < pc.roi_x || uv.x >= pc.roi_x + pc.roi_w ||
			uv.y < pc.roi_y || uv.y >= pc.roi_y + pc.roi_h) {
			mask_val = 0.0;
		}
	}

	// Logic masking if still foreground
	if (mask_val > 0.5) {
		if (pc.mask_mode == 0) { // Studio White
			if (color.r > pc.threshold && color.g > pc.threshold && color.b > pc.threshold) mask_val = 0.0;
		} else if (pc.mask_mode == 1) { // Chroma Green
			if (color.g > color.r + 0.1 && color.g > color.b + 0.1) mask_val = 0.0;
		} else if (pc.mask_mode == 2) { // Chroma Blue
			if (color.b > color.r + 0.1 && color.b > color.g + 0.1) mask_val = 0.0;
		} else if (pc.mask_mode == 3) { // Smart Studio
			float max_c = max(color.r, max(color.g, color.b));
			float min_c = min(color.r, min(color.g, color.b));
			if (max_c - min_c < 0.1 && max_c > pc.threshold) mask_val = 0.0;
		}
	}

	imageStore(output_mask, uv, vec4(mask_val));
}
