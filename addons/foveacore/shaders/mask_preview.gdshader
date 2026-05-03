shader_type canvas_item;

uniform sampler2D source_image : hint_default_white;
uniform float threshold : hint_range(0.0, 1.0) = 0.95;
uniform int mask_mode = 0; // 0: White, 1: Green, 2: Blue, 3: Smart
uniform bool show_mask_overlay = true;
uniform vec4 mask_color : source_color = vec4(1.0, 0.0, 0.0, 0.4);  // Red tint for removed areas
uniform vec2 roi_pos = vec2(0.0, 0.0);
uniform vec2 roi_size = vec2(0.0, 0.0);
uniform bool show_roi = false;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	float mask_val = 1.0; // 1 = keep (foreground), 0 = remove (background)

	// Compute mask on GPU (same logic as masking_compute.glsl)
	if (mask_mode == 0) { // Studio White
		float brightness = (color.r + color.g + color.b) / 3.0;
		mask_val = brightness > threshold ? 0.0 : 1.0;
	} else if (mask_mode == 1) { // Chroma Green
		float green_bias = color.g - max(color.r, color.b);
		mask_val = green_bias > threshold * 0.5 ? 0.0 : 1.0;
	} else if (mask_mode == 2) { // Chroma Blue
		float blue_bias = color.b - max(color.r, color.g);
		mask_val = blue_bias > threshold * 0.5 ? 0.0 : 1.0;
	} else if (mask_mode == 3) { // Smart Studio
		float max_c = max(color.r, max(color.g, color.b));
		float min_c = min(color.r, min(color.g, color.b));
		float sat = max_c - min_c;
		mask_val = (max_c > threshold && sat < 0.1) ? 0.0 : 1.0;
	}

	vec4 final_color = color;

	// Show mask overlay
	if (show_mask_overlay && mask_val < 0.5) {
		// Apply semi-transparent tint
		final_color = mix(color, mask_color, mask_color.a);
	}

	// Show ROI border
	if (show_roi && roi_size.x > 0.0 && roi_size.y > 0.0) {
		vec2 p = UV * vec2(textureSize(TEXTURE, 0));
		vec2 roi_min = roi_pos;
		vec2 roi_max = roi_pos + roi_size;
		float border_width = 3.0;
		bool on_border = (
			(p.x >= roi_min.x - border_width && p.x <= roi_min.x + border_width && p.y >= roi_min.y && p.y <= roi_max.y) ||
			(p.x >= roi_max.x - border_width && p.x <= roi_max.x + border_width && p.y >= roi_min.y && p.y <= roi_max.y) ||
			(p.y >= roi_min.y - border_width && p.y <= roi_min.y + border_width && p.x >= roi_min.x && p.x <= roi_max.x) ||
			(p.y >= roi_max.y - border_width && p.y <= roi_max.y + border_width && p.x >= roi_min.x && p.x <= roi_max.x)
		);
		if (on_border) {
			final_color = vec4(1.0, 1.0, 0.0, 1.0); // Yellow border
		}
	}

	COLOR = final_color;
}
